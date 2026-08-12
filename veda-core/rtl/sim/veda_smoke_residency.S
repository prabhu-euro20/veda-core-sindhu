.section .text
.global _start
// RTL-6 (DESIGN_02 Phase 2, increment 1): the OBJECT RESIDENCY GATE.
//
// Mirrors the Sail test of the same claim. Object_ID=104 is reset-seeded
// VALID but NOT RESIDENT, in a resident region, so the object gate is the
// only fault that can fire on it.
//
// PART A -- ALL THREE BIND MODES HARD-TRAP 0x0A.
// This is the whole point of the test and the reason it is not one bind
// but three. The two violations sitting textually next to the residency
// gate in the RTL (wrong-owner, object-not-found) are BOTH gated on plain
// Bind only; the region fault next to them is deliberately NOT. Copying
// the wrong neighbour is a one-token mistake that compiles clean, and it
// would leave Bind-NoTrap and Rebind silently soft-failing with a cleared
// Tag -- reporting "your object is gone" for an object that is merely
// paged out, so the pager is never invoked and a live object looks
// permanently destroyed. Only a test that exercises all three modes can
// tell those two designs apart.
//
// PART B -- THE FAULT COMMITS NOTHING.
// A trapping instruction must not mutate architectural state. Two things
// are checked: the destination capability register is untouched (Tag still
// 0), and -- checked in the testbench against odt_mem directly -- the ODT
// owner byte was NOT claimed. The second is the one that matters: a
// residency-faulting Bind that still writes MHARTID would take ownership
// of an object it was just refused, and because page-in is specified to
// PRESERVE owner_hart, that stolen ownership would survive the entire
// paging cycle and outlive the fault that created it.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            // trap counter

    // ═══ PART A1: plain Bind -- must hard-trap 0x0A ═══
    li   x1, 104
    .insn i 0x0b, 0x5, x3, x1, 0           // veda.bind c3, x1
    li   t1, 1
    bne  x20, t1, fail
    li   t1, 0x6A                          // (cap_idx 3 << 5) | cause 0x0A
    bne  x25, t1, fail
    li   x21, 0x600D

    // ═══ PART A2: Bind-NoTrap -- must ALSO hard-trap, not soft-fail ═══
    // If this mode were wrongly gated out it would take no trap at all and
    // merely clear c4's Tag, so the trap COUNT is the discriminator here,
    // not just the cause.
    li   x1, 104
    .insn i 0x0b, 0x5, x4, x1, 1           // veda.bind.notrap c4, x1
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x8A                          // (cap_idx 4 << 5) | cause 0x0A
    bne  x25, t1, fail
    li   x22, 0x600D

    // ═══ PART A3: Rebind -- must ALSO hard-trap ═══
    // Rebind is architecturally trap-free everywhere except the region
    // fault; object residency is the SECOND condition ever to make it
    // trap, and the same argument applies -- a Tag-clear would report
    // destruction where the truth is recoverable.
    li   x1, 104
    .insn i 0x0b, 0x5, x5, x1, 2           // veda.rebind c5, x1
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0xAA                          // (cap_idx 5 << 5) | cause 0x0A
    bne  x25, t1, fail
    li   x23, 0x600D

    // ═══ PART B: nothing committed ═══
    // c3 was the plain-Bind target and must be completely untouched --
    // Tag 0, exactly as it was at reset.
    .insn r 0x5b, 0x0, 0x03, x24, x3, x0   // cgettag x24, c3
    bne  x24, x0, fail
    li   x26, 0x600D

    // A resident object still binds normally afterwards, proving the gate
    // refuses one specific object rather than having broken Bind outright.
    li   x1, 1
    .insn i 0x0b, 0x5, x6, x1, 0           // veda.bind c6, x1
    li   t1, 3
    bne  x20, t1, fail                     // no new trap
    .insn r 0x5b, 0x0, 0x03, x27, x6, x0   // cgettag x27, c6
    li   t1, 1
    bne  x27, t1, fail
    li   x28, 0x600D

    // ═══ PART C: REBINDING A LIVE CAPABILITY ONTO A PAGED-OUT OBJECT ═══
    // Added after mutation testing: removing Rebind's own residency
    // exclusion left every check above passing. The reason is worth
    // recording, because it is a general trap in writing these tests.
    //
    // Rebind's field writes are gated on `!sealed && valid && owner_ok`.
    // PART A3 rebinds into c5, which is UNTOUCHED SINCE RESET and
    // therefore reads as sealed -- so the write was suppressed by the
    // seal check, not by the residency gate, and the two designs agreed.
    // The test was measuring the wrong guard.
    //
    // The real attack needs a capability that passes all three: bind c8 to
    // a live, resident object first, THEN rebind it onto the paged-out
    // one. Without the exclusion, `valid` is true for a paged-out object
    // by construction, so Rebind writes object 104's stale Base into a
    // capability whose Tag stays 1 -- a live capability now pointing at a
    // frame the pager is free to have handed to someone else. That is the
    // use-after-free this whole increment exists to prevent, reached
    // through the one bind mode that was never meant to trap.
    li   x1, 1
    .insn i 0x0b, 0x5, x8, x1, 0           // veda.bind c8, x1  (resident)
    .insn r 0x5b, 0x0, 0x00, x29, x8, x0   // cgetbase x29, c8
    li   t1, 0x80010000
    bne  x29, t1, fail                     // precondition: c8 is object 1

    li   x1, 104
    .insn i 0x0b, 0x5, x8, x1, 2           // veda.rebind c8, x1 -> must trap
    li   t1, 4
    bne  x20, t1, fail
    li   t1, 0x10A                         // (cap_idx 8 << 5) | cause 0x0A
    bne  x25, t1, fail

    // THE ASSERTION: c8 must be exactly as it was. Base unchanged proves
    // the paged-out entry was never read into it; Tag still 1 proves the
    // trap did not degrade a valid capability either.
    .insn r 0x5b, 0x0, 0x00, x29, x8, x0   // cgetbase x29, c8
    li   t1, 0x80010000
    bne  x29, t1, fail                     // NOT 0x80010300 (object 104)
    .insn r 0x5b, 0x0, 0x03, x31, x8, x0   // cgettag x31, c8
    li   t1, 1
    bne  x31, t1, fail
    li   x19, 0x600D

    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x26, t1, fail
    bne  x28, t1, fail
    bne  x19, t1, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    csrr t5, mcause
    li   t6, 0x18
    bne  t5, t6, fail                      // every fault here is a Veda trap
    csrr x25, mtval
    addi x20, x20, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
fail:
    li   x30, 0xBAD
done:
    j    done
