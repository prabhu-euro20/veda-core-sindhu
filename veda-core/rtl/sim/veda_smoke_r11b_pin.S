.section .text
.global _start
// RTL-9 (R11(b), DESIGN_07 Tier H): YOU MAY NOT EVICT THE CODE YOU ARE
// RUNNING.
//
// Mirrors the Sail test vc_r11b_executing_pin_neg.S.
//
// THE GAP RTL-7 COULD NOT CLOSE. RTL-7 revalidates the code object at the
// three crossings, which closes ENTERING an object evicted while you were
// away. It can do nothing about eviction of the object you are CURRENTLY
// executing, because fetch compares the PC against PCC's cached Base and
// Length and never re-reads the table. PCC had bounds and no name, so the
// core could not even say which object backed the running compartment.
//
// PART A1 -- page-out of the running object is refused.
// PART A2 -- destroy likewise, AND it runs after a trap round-trip, so it
//            only refuses if mret restored the NAME along with the bounds.
// PART A4 -- POPULATE likewise. This is the part that matters most. A
//            repopulate of a still-valid slot bumps generation and repoints
//            Base/Length/Perms, so it does everything Destroy does and
//            more -- refusing Destroy while leaving Populate open would be
//            a bypassable refusal, not a partial one.
// PART B  -- the SAVED name pins too: inside the handler PCC belongs to no
//            object, yet the compartment's object still cannot be evicted,
//            because a return to it is owed.
// PART C  -- the RELEASE. The same instruction on the same object that was
//            refused in PART B SUCCEEDS once OCRETURN abandons the frame.
//            A pin that never released would be denial of revocation, so
//            this is a security assertion and not a convenience one.
// PART D  -- the over-refusal control: an unrelated live object stays
//            evictable while a compartment runs. Without it a core that
//            refused every eviction outright would pass everything above.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0                            // trap counter

    // ---- CODE attr: Length UNBOUNDED, Permit_Execute|Permit_Invoke
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- CODE
    la   x7, after_pad
    li   x1, 184
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- PART C landing

    // ---- DATA attr for the invoke handoff: Permit_Invoke, NOT executable
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0400
    csrw 0x7C4, x6
    la   x7, data_pad
    li   x1, 181
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7
    la   x7, victim_pad
    li   x1, 183
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // the PART D control object

    // ---- type authority: Permit_Seal|Permit_Unseal
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0300
    csrw 0x7C4, x6
    la   x7, auth_pad
    li   x1, 182
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7

    // A control taken BEFORE entering: 180 is evictable right now, because
    // nothing is executing it. It MUST run ahead of the binds -- page-out
    // bumps generation, so a capability minted before this round-trip is
    // already dead by the time it is used.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // page.out 180 -- must SUCCEED
    bne  x20, x0, fail
    la   x7, compartment
    li   x1, 180
    .insn r 0x0b, 0x0, 0x05, x5, x1, x7    // page.in 180 -- resident again
    bne  x20, x0, fail
    li   x19, 0x600D

    li   x1, 180
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 180  -- CODE
    li   x1, 181
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, 181  -- DATA
    li   x1, 182
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, 182  -- authority
    li   x1, 184
    .insn i 0x0b, 0x5, x8, x1, 0           // veda.bind c8, 184  -- CODE
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    // cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    // cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x15, x13, x8, x0   // csealentry c13, c8 -- PART C

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    // ocinvoke c3, c4 -- ENTER 180
    j    fail

.balign 4
compartment:
    // PCC now names object 180.

    // ═══ PART A1: page out our own code object. MUST REFUSE. ═══
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // page.out 180 -- REFUSED (trap 1)
    li   x9, 1
    bne  x20, x9, fail
    li   x9, 2
    bne  x21, x9, fail                     // mcause 2 = Illegal_Instruction

    // ═══ PART A2: destroy our own code object. MUST REFUSE. ═══
    // Reached only after mret restored PCC, so this also proves the name
    // came back with the bounds.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    // destroy 180 -- REFUSED (trap 2)
    li   x9, 2
    bne  x20, x9, fail
    bne  x15, x9, fail

    // ═══ PART A4: REPOPULATE our own code object. MUST REFUSE. ═══
    // The bypass. Populate on a still-valid slot bumps generation and
    // repoints Base -- strictly more than Destroy -- so leaving it open
    // would make the two refusals above decorative.
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, victim_pad
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast 180 -- REFUSED (3)
    li   x9, 3
    bne  x20, x9, fail
    li   x9, 2
    bne  x23, x9, fail
    li   x26, 0x600D

    // ═══ PART A5: THE ALIAS. Object_ID 436 is a DIFFERENT name, but this
    // core resolves entries as region_base + local[7:0], and 436's low
    // byte is 180 -- so it lands on the very 32 bytes backing the code
    // being executed. A pin that compared NAMES would wave this through
    // and let an authorized actor clear the running object's descriptor in
    // one instruction. The id_hi tag that exists to catch aliasing is
    // consulted only on the two READ paths, never on an ODT write.
    //
    // This case cannot arise on the Sail model at all -- there an entry is
    // base(region) + the FULL 24-bit local, so names and slots are in
    // bijection and 436 is genuinely a different entry. It is reachable
    // only here, which is why it had to be found and tested here.
    li   x1, 436
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    // destroy 436 -- REFUSED (trap 4)
    li   x9, 4
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail

    // ═══ PART A6: THE REFUSALS DID NOT HALF-APPLY. ═══
    // A refusal that still writes the table is worse than no refusal at
    // all: the trap says "denied" while the descriptor is already gone.
    // The trap assertions above cannot see that -- suppressing the ODT
    // write and raising the trap are two separate signals here, and a
    // mutant that keeps the trap and drops the suppression passes every
    // check above. Re-Bind 180 and read its Base back: a half-applied
    // Destroy would fail the Bind outright, and a half-applied Populate
    // would return victim_pad instead of the compartment.
    li   x1, 180
    .insn i 0x0b, 0x5, x12, x1, 0          // veda.bind c12, 180
    li   x9, 4
    bne  x20, x9, fail                     // the Bind itself must not trap
    .insn r 0x5b, 0x0, 0x00, x16, x12, x0  // cgetbase x16, c12
    la   x17, compartment
    bne  x16, x17, fail                    // Base untouched by any refusal
    li   x22, 0x600D

    // ═══ PART D: an UNRELATED live object is still evictable. ═══
    li   x1, 183
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // page.out 183 -- must SUCCEED
    li   x9, 4
    bne  x20, x9, fail                     // no new trap
    li   x24, 0x600D

    // ---- hand control to the handler with a return to 180 still owed
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x11, x5, x10  // ocl.d c11 -- untagged, TRAPS (5)
    j    fail

.balign 4
// Scratch is x9/x14 and raw x-numbered registers. t5/t6 are x30/x31 and
// x30 is the result register here; naming the ABI alias hides that
// collision one table away, which has cost this project four debugging
// cycles.
trap_handler:
    addi x20, x20, 1
    li   x9, 1
    beq  x20, x9, rec_a1
    li   x9, 2
    beq  x20, x9, rec_a2
    li   x9, 3
    beq  x20, x9, rec_a4
    li   x9, 4
    beq  x20, x9, rec_a5
    li   x9, 6
    beq  x20, x9, rec_b1
    li   x9, 7
    beq  x20, x9, rec_b2
    li   x9, 8
    beq  x20, x9, rec_b3
    li   x9, 5
    bne  x20, x9, fail

    // ═══ trap 5: in the handler. depth is 1, PCC belongs to NO object,
    //     and the saved name is 180. ═══
    csrr x9, mcause
    li   x14, 0x18
    bne  x9, x14, fail

    // ═══ PART B: the saved name pins all three eviction paths. ═══
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // page.out 180 -- REFUSED (6)
    li   x1, 180
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    // destroy 180 -- REFUSED (7)
    la   x7, victim_pad
    li   x1, 180
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast 180 -- REFUSED (8)
    li   x9, 8
    bne  x20, x9, fail
    li   x9, 2
    bne  x27, x9, fail
    bne  x28, x9, fail
    bne  x29, x9, fail
    li   x18, 0x600D                       // PART B's own success marker --
                                           // x27/x28/x29 are mcause RECORDS
                                           // (value 2), not markers, and the
                                           // first testbench asserted 0x600D
                                           // on one of them. The RTL was
                                           // right and the check was wrong.

    // ═══ PART C: abandon the frame. OCRETURN into a DIFFERENT object must
    //     release 180's pin. ═══
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0   // ocreturn c13 -- lands in 184
    j    fail

rec_a1:
    csrr x21, mcause
    j    resume
rec_a2:
    csrr x15, mcause
    j    resume
rec_a4:
    csrr x23, mcause
    j    resume
rec_a5:
    csrr x25, mcause
    j    resume
rec_b1:
    csrr x27, mcause
    j    resume
rec_b2:
    csrr x28, mcause
    j    resume
rec_b3:
    csrr x29, mcause
    j    resume
resume:
    csrr x14, mepc
    addi x14, x14, 4
    csrw mepc, x14
    mret

.balign 4
after_pad:
    // Reached only by PART C's OCRETURN. The frame is gone and 180 is owed
    // to nobody, so the pin must be released.
    li   x1, 180
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    // page.out 180 -- must SUCCEED NOW
    li   x9, 8
    bne  x20, x9, fail                     // still exactly eight traps

    li   x9, 0x600D
    bne  x19, x9, fail
    bne  x24, x9, fail
    bne  x26, x9, fail
    bne  x18, x9, fail
    bne  x22, x9, fail
    li   x30, 0xD09E
    j    done
fail:
    li   x30, 0xBAD
done:
    j    done

.section .data
.balign 32
data_pad:
    .zero 0x100
.balign 32
victim_pad:
    .zero 0x100
.balign 32
auth_pad:
    .zero 0x100
