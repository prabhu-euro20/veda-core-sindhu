.section .text
.global _start
// R23 -- the two RTL-only defects found while GROUNDING the R19 check-reorder,
// neither of which any existing test could see. Both fixes are already in
// veda_core.tlv; this is the test that was owed.
//
// PHASE A -- the capability bounds check asked whether SIXTEEN bytes fit for a
// THIRTY-TWO byte access ($veda_oclc_bounds_ok used 65'd16). Sail always passed
// 32, so this was RTL-only. For an object of Length L, offset L-16 satisfies
// (L-16)+16 <= L, so the check PASSED, and the access then reached Base+L+15 --
// sixteen bytes PAST the object, with a valid capability and no trap.
//
//   Object 20 is minted with Length 48 DELIBERATELY, and 48 is the whole point.
//   OCS.C requires 32-byte alignment ($veda_capmem_misaligned, judged on the
//   RESOLVED address), so the only usable offsets are multiples of 32. The
//   distinguishing offset must satisfy  L-32 < offset <= L-16  AND  offset%32==0.
//   The seeded Length-64 object 1 has NO such offset -- every 32-aligned offset
//   behaves identically under both widths, which is exactly why the corpus
//   never caught this. At L=48, offset 32 is the discriminator:
//     old 65'd16 : 32+16 = 48 <= 48  -> PASSES, writes through Base+63, i.e.
//                                       16 bytes past the object end at Base+48
//     new 65'd32 : 32+32 = 64 >  48  -> BOUNDS_VIOLATION 0x01, as it must
//
// PHASE B -- veda.rebind handed out $veda_odt_perms verbatim with no cow test,
// three lines below the Bind arm that masks with 16'hFFF7, and directly under a
// comment asserting "a copy-on-write object never hands out store permission,
// however often it is bound". The file contradicted its own written intent.
// Sail masks BOTH paths via veda_bind_perms. Single-bit discriminator: bit 3.
//
// PHASE C -- the control. An IN-BOUNDS OCS.C on the same object must still
// succeed. Without it, Phase A proves only "OCS.C traps", not "OCS.C traps at
// the right boundary" -- the difference between a test and a tautology.
//
// REGISTER DISCIPLINE, and it is not decoration: this corpus has been bitten
// FIVE times by ABI-named scratch registers silently clobbering a result. Every
// register here is written as an explicit x-name and the handler touches only
// x20/x21/x22/x29. Do not "tidy" these into t0/t1/a0 names.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0                       // trap count
    li   x21, 0                       // last mcause
    li   x22, 0                       // last mtval

    // ================= PHASE A =================
    // Mint Object_ID 20: Base=0x80010200 (32-byte aligned), Length=0x0030 (48),
    // Perms=0x000C (Permit_Load | Permit_Store).
    li   x1, 20
    li   x2, 0x800102000030000C       // {Base[31:0], Length[15:0], Perms[15:0]}
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 20
    .insn i 0x0b, 0x5, x2, x1, 0      # veda.bind c2, 20

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0      # veda.bind c0, 1   (a real capability to store)

    li   x3, 32                       // the discriminating offset
    .insn r 0x0b, 0x4, 0x01, x0, x2, x3   # ocs.c  mem=c2, off=x3, src=c0

    mv   x10, x22                     // mtval of the trap this SHOULD have taken
    mv   x11, x20                     // trap count after phase A (must be 1)

    // ================= PHASE B =================
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0      # veda.bind c1, 1
    .insn r 0x5b, 0x0, 0x02, x12, x1, x0  # cgetperm x12, c1  -- expect 0x100C

    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1

    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 2      # veda.REBIND c1, 1   (bind_mode = 2'b10)
    .insn r 0x5b, 0x0, 0x02, x13, x1, x0  # cgetperm x13, c1  -- expect 0x1004

    // leave object 1 un-cowed so nothing downstream inherits the policy
    li   x1, 1
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 0

    // ================= PHASE C (control) =================
    li   x3, 0                        // 0 + 32 = 32 <= 48 -- genuinely in bounds
    .insn r 0x0b, 0x4, 0x01, x0, x2, x3   # ocs.c  mem=c2, off=0, src=c0

    mv   x14, x20                     // trap count after phase C (must still be 1)

1:  j 1b

// ---- handler: count, record, step over the faulting instruction ----
trap_handler:
    addi x20, x20, 1
    csrr x21, mcause
    csrr x22, mtval
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
