.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-5 (R10, DESIGN_07 Tier G) POSITIVE round-trip:
    // the CRBR tracks the domain across invoke -> trap -> mret -> return,
    // observed directly through the new read-only CSRs 0x7C6
    // (veda_current_region) and 0x7C7 (veda_saved_region).
    //
    // This is the test the whole existing corpus cannot be: every other
    // crossing in the suite uses a region-0 code capability, so the CRBR
    // load always writes its own reset value, the trap save never fires,
    // and the mret restore is always a no-op. A green 62/62 after RTL-5
    // is therefore consistent with the CRBR arms being wired to constants
    // or to nothing at all. This crosses into region 1 (seeded RESIDENT
    // at rt_odt_base[1] = entry 256) so the mechanism actually moves.
    //
    // Proves four things:
    //   1. OCInvoke into a RESIDENT non-zero region succeeds and loads
    //      the CRBR   (0x7C6: 0 -> 1)
    //   2. A trap inside it RESETS the CRBR to region 0 and SAVES 1
    //      (in-handler 0x7C6 == 0, 0x7C7 == 1)
    //   3. mret RESTORES region 1, self-consuming (0x7C7 back to 0xFFFFF)
    //   4. Returning through a region-0 sentry loads the CRBR back to 0
    //
    // Object_IDs: region-1 CODE = (1<<24)|20 = 16777236, region-1 DATA =
    // (1<<24)|21 = 16777237, type authority = 45 (region 0), sentry
    // source = 46 (region 0). 45/46 confirmed unused elsewhere.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    // CRBR starts at its reset value, region 0.
    csrr x10, 0x7C6
    li   t2, 0
    bne  x10, t2, fail

    // -- region-0 SENTRY source (Object_ID 46): Base=return_landing,
    //    Length=0xFFFF (unbounded-ish), Perms=Execute. Minted BEFORE
    //    entry; capability registers survive OCInvoke, only PCC narrows.
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 46
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   // veda.odt.populate
    li   x1, 46
    .insn i 0x0b, 0x5, x8, x1, 0          // veda.bind c8, x1
    .insn r 0x5b, 0x1, 0x15, x9, x8, x0   // csealentry c9, c8  -- region-0 sentry

    // -- region-1 CODE object (Object_ID (1<<24)|20). Length 0x100 so the
    //    whole in-compartment sequence fits inside the PCC bound.
    la   t0, compartment_r1
    slli t0, t0, 32
    li   t1, 0x01000402                    // Length 0x0100, Perms Execute|Invoke
    or   t0, t0, t1
    li   x1, 16777236
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   // veda.odt.populate (region 1, resident)

    // -- region-1 DATA object, Invoke-only (non-executable).
    li   x1, 16777237
    li   x2, 0x8002000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    // -- type authority (region 0), Permit_Seal|Permit_Unseal.
    li   x1, 45
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 16777236
    .insn i 0x0b, 0x5, x0, x1, 0          // veda.bind c0, x1  -- region-1 CODE
    li   x1, 16777237
    .insn i 0x0b, 0x5, x1, x1, 0          // veda.bind c1, x1  -- region-1 DATA
    li   x1, 45
    .insn i 0x0b, 0x5, x2, x1, 0          // veda.bind c2, x1  -- authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   // cseal c3, c0, c2  -- sealed region-1 CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   // cseal c4, c1, c2  -- sealed region-1 DATA

    // (1) enter region 1 -- the CRBR must load region 1.
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   // ocinvoke c3, c4
    j    fail                              // must jump, not fall through
.balign 4
compartment_r1:
    csrr x11, 0x7C6                        // veda_current_region -- expect 1
    li   t2, 1
    bne  x11, t2, fail

    // (2) trap out; handler asserts the reset+save, then mrets back.
    ecall
resume_r1:
    // (3) restored to region 1, shadow self-consumed.
    csrr x12, 0x7C6                        // expect 1 again
    li   t2, 1
    bne  x12, t2, fail
    csrr x13, 0x7C7                        // veda_saved_region -- expect 0xFFFFF
    li   t2, 0xFFFFF
    bne  x13, t2, fail

    // (4) return through the region-0 sentry -- CRBR back to region 0.
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0   // ocreturn c9
    j    fail
.balign 4
return_landing:
    csrr x14, 0x7C6                        // expect 0
    li   t2, 0
    bne  x14, t2, fail
    li   x20, 0x600D
    j    done
.balign 4
trap_handler:
    // The handler runs in the ROOT domain: CRBR reset to 0, region 1 saved.
    csrr x15, 0x7C6                        // expect 0 in-handler
    li   t2, 0
    bne  x15, t2, fail
    csrr x16, 0x7C7                        // expect 1 (saved)
    li   t2, 1
    bne  x16, t2, fail
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    li   x21, 0xBAD
done:
1:
    j 1b
