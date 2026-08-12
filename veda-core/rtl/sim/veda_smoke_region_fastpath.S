.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-4 (DESIGN_08) test 2: the CRBR fast path is
    // FIXED-SHAPE -- one memory read for an intra-domain bind, exactly
    // one extra for a cross-domain bind, and NEVER anything else.
    //
    // This is the test that distinguishes a single architectural
    // register from a cache. A cache would show a read count that
    // depends on history: a miss on the first touch, hits afterwards,
    // evictions later. The CRBR must show a count that depends only on
    // WHICH DOMAIN the object is in -- never on how many times it has
    // been touched, never on what was touched before.
    //
    // So the shape is deliberate: THREE intra-domain binds, then ONE
    // cross-domain bind. The Region-Table read count must be 0 for the
    // whole first phase (not "0 after the first one") and exactly 1 for
    // the second. If the count scaled with intra-domain binds, the CRBR
    // would not be removing the read from the common path at all; if it
    // were 0 for the cross-domain bind, the RT would be being bypassed.
    //
    // It is also independent of DRAM_EXTRA_CYCLES, which is committed at
    // 0 -- the property is structural (how many reads), not temporal
    // (how many cycles), so it is proved by probing the read-enable
    // rather than by timing.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    // ---- PHASE 1: three INTRA-domain binds (region 0 == the CRBR's
    // current region). Region-Table reads must stay at ZERO throughout.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          // veda.bind c1, x1
    li   x2, 2
    .insn i 0x0b, 0x5, x2, x2, 0          // veda.bind c2, x2
    li   x3, 1
    .insn i 0x0b, 0x5, x3, x3, 0          // veda.bind c3, x3  (same object again)
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  // cgettag x10, c1  -- expect 1
    .insn r 0x5b, 0x0, 0x03, x11, x2, x0  // cgettag x11, c2  -- expect 1
    .insn r 0x5b, 0x0, 0x03, x12, x3, x0  // cgettag x12, c3  -- expect 1
    li   x20, 0xFA57                       // marker: intra-domain phase over

    // ---- PHASE 2: one CROSS-domain bind (region 1). Exactly ONE extra
    // Region-Table read, and no more.
    li   x4, 16777217                      // (1 << 24) | 1
    .insn i 0x0b, 0x5, x4, x4, 0          // veda.bind c4, x4
    .insn r 0x5b, 0x0, 0x03, x13, x4, x0  // cgettag  x13, c4  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x14, x4, x0  // cgetbase x14, c4  -- expect 0x80020000
    li   x21, 0xD09E
    j    done

trap_handler:
    csrr x18, mcause
    csrr x19, mtval
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    li   x22, 0xBAD
    mret

done:
1:
    j 1b
