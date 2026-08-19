.section .text
.global _start
// RTL-7 (R11, DESIGN_07 Tier H): A DOMAIN CROSSING MUST REVALIDATE ITS
// CODE OBJECT.
//
// Mirrors the Sail tests vc_r11_crossing_evicted_neg and
// vc_r11_ocreturn_evicted_neg.
//
// THE GAP. The three crossings were the only consumers of an object's Base
// that never re-read the ODT, so a sealed CODE capability survived an
// eviction that a DATA capability to the same object did not. Reproduced
// on the Sail model with a control: after the same page-out, veda.bind
// refused with RESIDENCY while ocinvoke took the jump.
//
// WHY THE CAUSE IS 0x02 AND NOT 0x0A. Page-out BUMPS the generation, so a
// capability held across it fails the generation check before residency is
// ever consulted. That is the Option-A contract working as chosen, not a
// defect: the CAPABILITY is permanently dead because its generation is
// gone forever, while the OBJECT is still serviceable -- and software
// learns that difference by re-Binding, which reports 0x0A. Held
// capability gets the permanent verdict; fresh Bind gets the serviceable
// one. The first version of the Sail test asserted 0x0A and was wrong.
//
// PART A -- OCInvoke through a paged-out code object traps 0x02.
// PART B -- OCReturn likewise. Sail-side mutation testing proved this arm
//           needs its own coverage: deleting OCRETURN's revalidation left
//           the entire suite passing while the other two crossings were
//           covered. It is also the crossing where an evicted object is
//           most likely in practice -- a callee runs for an unbounded
//           time and the caller's code object is exactly the cold page a
//           pager evicts.
// PART C -- the positive control. A crossing into a live, resident object
//           still lands. Without it, a core that trapped on every crossing
//           would pass everything above.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0                            // trap counter

    // veda_attr: Length UNBOUNDED, Perms = Permit_Execute(1)|Permit_Invoke(10)
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6

    la   x7, invoke_pad
    li   x1, 160
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- CODE for PART A
    la   x7, return_pad
    li   x1, 161
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- CODE for PART B
    la   x7, control_pad
    li   x1, 162
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- CODE for PART C

    // a DATA object (Permit_Invoke, non-executable) for the invoke handoff
    li   x1, 163
    li   x2, 0x8001100000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // veda.odt.populate
    // a type authority (Permit_Seal | Permit_Unseal)
    li   x1, 164
    li   x2, 0x8001110000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // veda.odt.populate

    li   x1, 163
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, x1  -- DATA
    li   x1, 164
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, x1  -- authority
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    // cseal c4, c1, c2  -- sealed DATA

    li   x1, 160
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, x1
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    // cseal c3, c0, c2  -- sealed CODE A
    li   x1, 161
    .insn i 0x0b, 0x5, x8, x1, 0           // veda.bind c8, x1
    .insn r 0x5b, 0x1, 0x15, x9, x8, x0    // csealentry c9, c8 -- SENTRY for B
    li   x1, 162
    .insn i 0x0b, 0x5, x10, x1, 0          // veda.bind c10, x1
    .insn r 0x5b, 0x1, 0x10, x11, x10, x2  // cseal c11, c10, c2 -- sealed CODE C

    // ═══ PART A: page out 160, then OCInvoke through c3 ═══
    li   x1, 160
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // veda.odt.page.out

    // the capability's tag is untouched -- this design checks at USE, which
    // is exactly why the check has to exist AT the use
    .insn r 0x5b, 0x0, 0x03, x12, x3, x0   // cgettag x12, c3
    li   x13, 1
    bne  x12, x13, fail                    // fixture sanity

    // R50 increment 2: this file predates the crossing's retain mask and
    // measures a different mechanism, so it declares RETAIN ALL. The burden
    // of proving the clear works sits on veda_smoke_r50i2_crossing_clear.S.
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    // ocinvoke c3, c4 -- must TRAP
    li   x13, 1
    bne  x20, x13, fail                    // exactly one trap
    li   x13, 0x62                         // (cap_idx 3 << 5) | cause 0x02
    bne  x25, x13, fail
    li   x21, 0x600D

    // ═══ PART A2: OCJALR through the same paged-out object ═══
    // Added because mutation testing showed OCJALR's revalidation could be
    // deleted with all 70 tests passing. That is the SECOND time this
    // increment: on the Sail side the untested crossing was OCReturn, here
    // it was OCJALR. A fix spanning three sites gets tested on two unless
    // the sites are enumerated deliberately rather than by example.
    //
    // OCJALR unseals c3 via the type authority c2, then jumps to c3.Base --
    // so it consumes the object's Base exactly as the two real crossings
    // do, and needs the identical check despite being intra-domain.
    .insn r 0x5b, 0x1, 0x14, x0, x3, x2    // ocjalr c3, c2 -- must TRAP
    li   x13, 2
    bne  x20, x13, fail
    li   x13, 0x62                         // (cap_idx 3 << 5) | cause 0x02
    bne  x25, x13, fail
    li   x24, 0x600D

    // ═══ PART B: page out 161, then OCReturn through the sentry c9 ═══
    li   x1, 161
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // veda.odt.page.out

    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0    // ocreturn c9 -- must TRAP
    li   x13, 3
    bne  x20, x13, fail
    li   x13, 0x122                        // (cap_idx 9 << 5) | cause 0x02
    bne  x25, x13, fail
    li   x22, 0x600D

    // ═══ PART D: DESTROY-THEN-REPOPULATE -- the discriminating fixture ═══
    // Mutation testing showed the generation term could be deleted from
    // OCInvoke's violation OR with all 70 tests passing. The reason is
    // structural: after a PAGE-OUT both halves are true at once (generation
    // bumped AND residency cleared), so an OR of them cannot distinguish
    // either half's removal. Every earlier part of this test pages out, so
    // every earlier part measures the pair, not the terms.
    //
    // Destroy-then-repopulate separates them: the slot is valid again,
    // RESIDENT again, and its generation has moved. Only the generation
    // term can catch it. This is also the exact case that makes the
    // execute-view revocation claim real -- a destroyed object whose slot
    // is immediately reused is precisely when a stale code capability must
    // not still enter.
    li   x1, 165
    la   x7, dead_pad
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast
    li   x1, 165
    .insn i 0x0b, 0x5, x14, x1, 0          // veda.bind c14, x1
    .insn r 0x5b, 0x1, 0x10, x15, x14, x2  // cseal c15, c14, c2
    li   x1, 165
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    // veda.odt.destroy  -- gen bumped
    li   x1, 165
    la   x7, dead_pad
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // repopulate: valid + RESIDENT again

    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x15, x4   // ocinvoke c15, c4 -- must TRAP 0x02
    li   x13, 4
    bne  x20, x13, fail
    li   x13, 0x1E2                        // (cap_idx 15 << 5) | cause 0x02
    bne  x25, x13, fail
    li   x26, 0x600D

    // ═══ PART E: OCJALR cause ORDERING -- execute-perm outranks the new arms
    // Object 166 is sealed but carries NO Permit_Execute. Paged out, both
    // new terms are true -- but the correct chain reports 0x11, because a
    // capability that is not executable would not have crossed anyway.
    // Demoting execute-perm back to the implicit default (which is what it
    // was before this increment) makes this report 0x02 instead, and no
    // other test can see the difference.
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0400                    // Permit_Invoke only -- NO Execute
    csrw 0x7C4, x6
    li   x1, 166
    la   x7, dead_pad
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast
    li   x1, 166
    .insn i 0x0b, 0x5, x6, x1, 0           // veda.bind c6, x1
    .insn r 0x5b, 0x1, 0x10, x7, x6, x2    // cseal c7, c6, c2
    li   x1, 166
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // veda.odt.page.out

    .insn r 0x5b, 0x1, 0x14, x0, x7, x2    // ocjalr c7, c2 -- must TRAP 0x11
    li   x13, 5
    bne  x20, x13, fail
    li   x13, 0xF1                         // (cap_idx 7 << 5) | cause 0x11
    bne  x25, x13, fail
    li   x27, 0x600D

    // ═══ PART C: the positive control -- 162 is live and resident ═══
    li   x23, 0x600D
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x11, x4   // ocinvoke c11, c4 -- must SUCCEED
    j    fail                              // fell through without jumping

.balign 4
invoke_pad:
    j    fail                              // 160 is paged out; never reached
.balign 4
return_pad:
    j    fail                              // 161 is paged out; never reached
.balign 4
dead_pad:
    j    fail                              // PARTS D/E never legitimately land
.balign 4
control_pad:
    // Reached only via PART C's crossing into a live, resident object.
    li   x13, 5
    bne  x20, x13, fail                    // still exactly five traps
    li   x13, 0x600D
    bne  x21, x13, fail
    bne  x22, x13, fail
    bne  x23, x13, fail
    bne  x24, x13, fail
    bne  x26, x13, fail
    bne  x27, x13, fail
    li   x30, 0xD09E
    j    done

.balign 4
// Scratch is x16/x17 -- raw x-registers, not ABI aliases. t5/t6 are x30/x31
// and both are result registers here; naming the alias hides that collision
// one ABI table away, which has cost this project four debugging cycles.
trap_handler:
    csrr x16, mcause
    li   x17, 0x18
    bne  x16, x17, fail                    // every fault here is a Veda trap
    csrr x25, mtval
    addi x20, x20, 1
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x30, 0xBAD
done:
    j    done
