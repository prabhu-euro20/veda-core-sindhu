.section .text
.global _start
_start:
    // RTL Milestone 16 negative control: the slot that has genuinely exhausted
    // its generation counter is PERMANENTLY RETIRED -- a re-populate is
    // refused, and the capability that predates the exhaustion hard-traps
    // instead of dereferencing memory it lost at the first Destroy.
    //
    // ═══ R49 -- THIS TEST WAS DARK FOR TWENTY INCREMENTS, AND THE WIDENING
    //     HAD ALREADY DELETED ITS PREMISE ═══════════════════════════════════
    //
    // It used to destroy Object_ID 200 in a loop 256 TIMES, because the
    // generation counter was 8 bits and 256 destroys wrapped it exactly onto a
    // stale capability's cached value. Increment 3 widened generation to 24
    // bits. 256 destroys now reach 0x000100 -- nowhere near the 0xFFFFFF
    // ceiling -- so the re-populate SUCCEEDED, the stale access did NOT trap,
    // and this file asserted the opposite of what the machine does.
    //
    // Nothing said so, because nothing ran it: run_veda_smoke_test.sh
    // assembled 96 images and simulated 90, and this was one of the seven it
    // built and skipped. The widening looked free precisely because its own
    // regression test had gone dark in the same era.
    //
    // Re-aimed rather than deleted. The RTL already seeds two NEAR-SATURATED
    // fixtures for the paging work (veda_core.tlv: Object_ID 106 at generation
    // 0xFFFFFE, one step below the ceiling; 108 at 0xFFFFFD). Two Destroys on
    // 106 reach the ceiling and retire the slot, so the property is measured
    // in TWO instructions instead of 256 -- and it is measured at the real
    // 24-bit width rather than at a width the architecture no longer has.
    // This is the same fixture-injection discipline Sail already uses for the
    // identical property (sail_tests/vc_gen_retire.S, vc_gen_retire_neg.S).
    //
    // RTL-11 (R14): the retired-slot refusal TRAPS. Two traps are expected:
    // the refused re-populate (resume past it) and the stale access.
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0

    // Object_ID 106 is seeded VALID at generation 0xFFFFFE, Base 0x80010500,
    // Length 0x40, Perms 0x000C (Load|Store). No populate needed -- and none
    // is possible at this generation without first exhausting it, which is the
    // whole point.
    li   x1, 106
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- caches generation 0xFFFFFE

    // Sanity: the capability genuinely works BEFORE the exhaustion. Without
    // this, a machine on which c0 never worked at all would pass every
    // assertion below for the wrong reason.
    li   x2, 0
    li   x7, 0x5A5A5A5A
    .insn r 0x0b, 0x3, 0x01, x7, x0, x2  # ocs.d c0, x2, x7
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0
    li   x18, 0x5A5A5A5A
    bne  x8, x18, done                   # x19 stays 0 -> the testbench fails
    li   x19, 0x600D                     # sanity passed

    // Destroy #1: 0xFFFFFE -> 0xFFFFFF. Slot invalid, NOT yet retired --
    // `new_retired` tests the OLD generation, so exhaustion is only observed
    // on the step that finds the counter already at the ceiling.
    li   x1, 106
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy

    // Destroy #2: the counter is already at the ceiling, so the bump would be
    // a silent no-op -- and THAT is what retires the slot forever.
    li   x1, 106
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy

    // The re-populate must now be REFUSED (retired), so object B is never
    // written into the slot.
    la   x5, array_b
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 106
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate -- MUST BE REFUSED

    // Use the ORIGINAL, now-stale c0. Since the re-populate was refused the
    // slot stayed invalid, so this must hard-trap rather than succeed.
    li   x18, 1
    bne  x20, x18, done                    // exactly one trap so far
    li   x18, 2
    bne  x21, x18, done                    // mcause 2 = illegal instruction
    li   x23, 0x600D
    li   x2, 0
fault_instr:
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0
    li   x22, 0xDEAD         # reached only if the retirement failed to bite
    j    done

trap_handler:
    addi x20, x20, 1
    csrr x21, mcause
    li   x18, 2
    beq  x20, x18, stale_access_trap
    // trap 1: the refused re-populate. Resume just past it.
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
stale_access_trap:
    li   x22, 0x600D         # the stale access correctly trapped
done:
1:
    j 1b

.section .data
.align 3
array_b:
    .dword 0xBBBBBBBBBBBBBBBB
