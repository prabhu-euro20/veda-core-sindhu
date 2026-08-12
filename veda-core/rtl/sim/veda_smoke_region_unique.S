.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-4 (DESIGN_08) test 1: GLOBAL UNIQUENESS across
    // protection domains, plus the dereference re-check.
    //
    // The 44-bit Object_ID is {region:20, local:24}. {region=0,local=1}
    // and {region=1,local=1} share a local, so under the pre-RTL-4 flat
    // table they were literally the same object. They must now resolve
    // to DIFFERENT ODT entries and therefore different objects -- the
    // single-address-space invariant DESIGN_08 Section 8 (i) names.
    //
    // Reset seeds (veda_core.tlv `initial`):
    //   Object_ID 1          = region 0, local 1 -> Base 0x80010000
    //   Object_ID 16777217   = region 1, local 1 -> Base 0x80020000
    //   (= (1 << 24) | 1; RT[1] is resident with odt_base = entry 256)
    //
    // The last step DEREFERENCES the region-1 capability. That is not
    // decoration: Bind and the dereference re-check are two separate,
    // hand-written copies of the ODT address computation ~700 lines
    // apart. If only Bind were region-ified, this bind would still
    // succeed and only the load would fail -- with cause 0x02
    // (generation-stale), from an entirely different fault family. No
    // region-0 test can ever catch that, because region 0's base is 0.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    // (1) region 0, local 1
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          // veda.bind c1, x1
    .insn r 0x5b, 0x0, 0x00, x10, x1, x0  // cgetbase x10, c1  -- expect 0x80010000
    .insn r 0x5b, 0x0, 0x03, x11, x1, x0  // cgettag  x11, c1  -- expect 1

    // (2) region 1, local 1 -- SAME local, DIFFERENT domain
    li   x2, 16777217
    .insn i 0x0b, 0x5, x2, x2, 0          // veda.bind c2, x2
    .insn r 0x5b, 0x0, 0x00, x12, x2, x0  // cgetbase x12, c2  -- expect 0x80020000
    .insn r 0x5b, 0x0, 0x03, x13, x2, x0  // cgettag  x13, c2  -- expect 1

    // (3) dereference the region-1 capability. Length is 8 and Perms is
    // 0x0004 (Permit_Load only), so an 8-byte load at offset 0 is
    // exactly in bounds. Reaching the sentinel below means the re-check
    // resolved through region 1's base too.
    li   x3, 0
    .insn r 0x0b, 0x3, 0x00, x14, x2, x3  // ocl.d x14, c2, x3
    li   x15, 0xD00D                       // reached => no trap on the dereference
    j    done

trap_handler:
    // Any trap at all is a failure for this test -- record why, so a
    // failure reports the real cause instead of just "did not finish".
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
