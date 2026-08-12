.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-4 (DESIGN_08) test 3 (negative): a paged-out domain
    // faults EXPLICITLY and BOUNDEDLY -- it never resolves silently.
    // This is the RTL statement of the cache-less pillar.
    //
    // Two arms of veda_region_is_resident (veda_regs.sail:499-505):
    //  (a) region 2 -- IN window, RT[2].rt_resident = 0. Its object IS
    //      seeded, valid and unowned at entry 512+7. That is the point:
    //      with a missing residency gate this bind would SUCCEED, not
    //      merely report a different cause. Object_ID = (2<<24)|7
    //      = 33554439, bound into c3 -> mtval (3<<5)|0x09 = 0x69.
    //  (b) region 9 -- OUT of the RT window (RT_ENTRIES = 8), so not
    //      modeled and therefore not resident. Object_ID = (9<<24)|1
    //      = 150994945, bound into c4 -> mtval (4<<5)|0x09 = 0x89.
    //
    // The load-bearing assertion is cause 0x09 and NOT 0x05. A
    // non-resident region also yields !odt_valid, so object-not-found
    // fires in the same cycle; if 0x05 won the priority chain, a domain
    // that is merely paged out would be reported as "never existed" and
    // the handler would give up where it should page the domain in and
    // retry. The full mtval word is checked, not just its low 5 bits,
    // because the cap_idx field has its own separate arm.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0
    li   x17, 0                            // trap counter

    // ---- (a) in-window, non-resident domain
    li   x3, 33554439                      // (2 << 24) | 7
fault1:
    .insn i 0x0b, 0x5, x3, x3, 0          // veda.bind c3, x3  -- must REGION_FAULT
    mv   x10, x18                          // mcause from (a)
    mv   x11, x19                          // mtval  from (a) -- expect 0x69
    .insn r 0x5b, 0x0, 0x03, x12, x3, x0  // cgettag x12, c3  -- expect 0, untouched

    // ---- (b) out-of-window domain
    li   x4, 150994945                     // (9 << 24) | 1
fault2:
    .insn i 0x0b, 0x5, x4, x4, 0          // veda.bind c4, x4  -- must REGION_FAULT
    mv   x13, x18                          // mcause from (b)
    mv   x14, x19                          // mtval  from (b) -- expect 0x89
    .insn r 0x5b, 0x0, 0x03, x15, x4, x0  // cgettag x15, c4  -- expect 0, untouched

    mv   x16, x17                          // trap count -- expect 2
    li   x21, 0xD09E
    j    done

trap_handler:
    csrr x18, mcause
    csrr x19, mtval
    addi x17, x17, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

done:
1:
    j 1b
