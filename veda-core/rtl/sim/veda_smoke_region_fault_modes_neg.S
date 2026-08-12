.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-4 (DESIGN_08) test 4 (negative): the region fault is
    // a HARD TRAP for ALL THREE bind modes, and it writes NOTHING.
    //
    // This is the test for the asymmetry veda_bind_insts.sail:145-147
    // mandates and that this file's own pre-existing plain-Bind-only
    // trap gating would otherwise silently drop. The reason it matters
    // is a security one rather than a symmetry one: a paged-out domain
    // is a RECOVERABLE, serviceable event. If Bind-NoTrap soft-failed
    // with a cleared Tag, or Rebind cleared Tag, the caller would be
    // told "your object is gone" instead of "your object's domain is
    // paged out, service it and retry" -- the pager would never be
    // invoked and a perfectly live object would look destroyed.
    //
    // Each phase PRELOADS the destination capability with a real bound
    // capability first, so "untouched" is genuinely observable. Without
    // the preload, a suppressed write and a Tag-clear on an already-zero
    // register are indistinguishable, and the test would pass either way.
    //
    // Region 2's Object_ID = (2 << 24) | 7 = 33554439 throughout.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0
    li   x17, 0                            // trap counter

    // ---- (a) Bind.NoTrap (mode 1) must HARD TRAP, not soft-fail.
    li   x1, 1
    .insn i 0x0b, 0x5, x3, x1, 0          // veda.bind c3, x1   -- preload c3 with a REAL capability
    li   x4, 33554439
    .insn i 0x0b, 0x5, x3, x4, 1          // veda.bind.notrap c3, x4 -- must REGION_FAULT
    mv   x10, x18                          // mcause -- expect 0x18
    mv   x11, x19                          // mtval  -- expect (3<<5)|0x09 = 0x69
    .insn r 0x5b, 0x0, 0x03, x12, x3, x0  // cgettag  x12, c3 -- STILL 1, Tag not cleared
    .insn r 0x5b, 0x0, 0x00, x13, x3, x0  // cgetbase x13, c3 -- STILL 0x80010000

    // ---- (b) Rebind (mode 2) must HARD TRAP and leave rd byte-identical.
    // Rebind is architecturally trap-free for every other failure reason
    // -- this is the first condition ever to make it hard-trap. Its
    // normal failure mode is a Tag-clear, which would look entirely
    // plausible here and would be wrong.
    li   x5, 1
    .insn i 0x0b, 0x5, x5, x5, 0          // veda.bind c5, x5   -- preload c5
    .insn r 0x5b, 0x0, 0x03, x14, x5, x0  // cgettag  x14, c5 -- expect 1 (precondition)
    li   x6, 33554439
    .insn i 0x0b, 0x5, x5, x6, 2          // veda.rebind c5, x6 -- must REGION_FAULT
    mv   x15, x18                          // mcause -- expect 0x18
    mv   x16, x19                          // mtval  -- expect (5<<5)|0x09 = 0xA9
    .insn r 0x5b, 0x0, 0x03, x20, x5, x0  // cgettag  x20, c5 -- STILL 1
    .insn r 0x5b, 0x0, 0x00, x23, x5, x0  // cgetbase x23, c5 -- STILL 0x80010000

    // ---- (c) plain Bind (mode 0), for completeness of the mode set.
    li   x7, 33554439
    .insn i 0x0b, 0x5, x7, x7, 0          // veda.bind c7, x7 -- must REGION_FAULT
    mv   x24, x19                          // mtval -- expect (7<<5)|0x09 = 0xE9

    mv   x25, x17                          // trap count -- expect 3
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
