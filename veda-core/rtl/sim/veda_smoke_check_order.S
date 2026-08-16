.section .text
.global _start
// R19 increment 1 -- the ORDER of the dereference cause chain, mirrored from
// Sail's vc_check_order.S.
//
// A 0x0C copy-on-write fault is not a refusal, it is a REPAIR REQUEST: it tells
// a handler to allocate, copy and hand back a fresh writable object. Raising it
// for an access that was going to be refused anyway arms that work for nothing.
// So every refusal now precedes every repair, and 0x0A precedes 0x0C because
// you cannot copy an object that is not in memory.
//
// WHY THIS FILE COVERS FIVE SEPARATE STORE FAMILIES. Sail routes every
// dereference through two shared checkers; this RTL inlines SEVEN cause chains,
// five of which carry a cow arm. An edit applied to four of five arms has
// already slipped through this project twice. One phase per cow-bearing chain
// is the only way a per-chain mutant can be attributed.
//
//   P1 ocs      P2 ocsc      P3 nmc_add.d      P4 nmc_add.w      P5 atomic
//   P6 residency-before-cow      P7 control      P8 the gate
//
// Object 1 is Base=0x80010000, Length=0x40, Perms=0x100C (Load|Store|NMC), so
// offset 64 is out of bounds for every width, and 0x80010040 is 32-byte aligned
// (which matters only for P2 -- a misaligned OCS.C would report 0x08 instead,
// and that would prove nothing about bounds-versus-cow).
//
// mtval is {cap_idx:5, cause:5}, so expected = cap<<5 | cause.
//
// Registers are written as explicit x-names throughout. This corpus has been
// bitten five times by ABI-named scratch silently clobbering a result -- do not
// "tidy" these into t0/a0 names.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 1   (BEFORE cow: keeps store)
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1

    // ---------- P1: ocs chain. Length-0 capability, the genuine closure ----------
    // csetbounds with rs2 = 0 yields a tagged, generation-current capability of
    // Length 0 in ONE instruction. Under the old order it stored, hit the cow arm
    // before bounds was consulted, took 0x0C, and a handler would have rebound it
    // to a FULL-Length capability minted from the entry.
    li   x2, 0
    .insn r 0x5b, 0x1, 0x08, x2, x1, x2   # csetbounds c2, c1, 0
    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x2, x2   # ocs.d through c2
    mv   x10, x22                          # want (2<<5)|0x01 = 0x41

    // ---------- P2: ocsc chain (the one that also has an 0x08 arm) ----------
    li   x2, 64                            # 64+32 > 64, and 32-byte aligned
    .insn r 0x0b, 0x4, 0x01, x1, x1, x2   # ocs.c  mem=c1, src=c1, off=64
    mv   x11, x22                          # want (1<<5)|0x01 = 0x21

    // ---------- P3/P4/P5: nmc_add.d, nmc_add.w and atomic ----------
    // THESE THREE TAKE THEIR OFFSET FROM THE CAPABILITY, NOT FROM A REGISTER.
    // $veda_nmc_bounds_ok_d is (rs1cap_offset + 8) <= rs1cap_length; the rs2
    // operand is the ADDEND, not an offset. A first draft of this test passed
    // 64 in rs2 expecting an out-of-bounds access and got 0x0C instead -- the
    // access was at offset 0 all along, comfortably in bounds, so the chain
    // correctly fell through to the cow arm. The RTL was right and the test was
    // wrong, which is worth writing down: OCS.D and NMC/atomic do not agree on
    // where an offset comes from.
    //
    // c4 is therefore a Length-0 capability, for which offset 0 is out of bounds
    // at every width -- the same construction P1 uses, and the only one that
    // works for a capability-offset instruction.
    li   x2, 0
    .insn r 0x5b, 0x1, 0x08, x4, x1, x2   # csetbounds c4, c1, 0  (perms carry: Load|Store|NMC)

    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x6, x4, x2   # nmc_add.d through c4
    mv   x12, x22                          # want (4<<5)|0x01 = 0x81

    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x6, x4, x2   # nmc_add.w through c4
    mv   x13, x22                          # want 0x81

    li   x2, 0
    .insn r 0x2b, 0x3, 0x00, x6, x4, x2   # veda.amoadd.d through c4
    mv   x14, x22                          # want 0x81

    // ---------- P6: residency outranks cow ----------
    // c11 names Object_ID 104, the reset-seeded valid-but-NON-RESIDENT fixture.
    // Marking it cow must NOT make it report 0x0C: it has to be paged in first,
    // or the handler copies from a frame the pager may already have reassigned.
    li   x1, 104
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 104 <- 1
    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x11, x2  # ocs.d through c11
    mv   x15, x22                          # want (11<<5)|0x0A = 0x16A

    // ---------- P7: control ----------
    // In bounds, resident, cow. Must STILL be 0x0C, or the arm is simply gone
    // and every phase above would pass for the wrong reason.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # re-bind c1 (P2 left it unchanged, be explicit)
    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2   # ocs.d through c1, offset 0
    mv   x16, x22                          # want (1<<5)|0x0C = 0x2C

    // ---------- P8: the gate ----------
    // c3 is bound while the object is ALREADY cow, so veda_bind_perms masks with
    // 16'hFFF7 and it lacks PERM_STORE by construction. It must still report
    // 0x0C "copy me", never 0x13 "you may not write" -- that is the whole job of
    // the !$veda_cow_write conjunct on the permission arm, and it is what keeps
    // copy-on-write reachable now that the cow arm sits at the bottom.
    //
    // This phase exists because the Sail mutant SURVIVED without it: removing the
    // gate was caught by nothing in a 94-test corpus, because every existing cow
    // test inspects the attenuated capability with CGetPerm and never
    // DEREFERENCES through it. Attenuation tested as bookkeeping, never as
    // enforcement -- the identical shape as the CAndPerm defect.
    li   x1, 1
    .insn i 0x0b, 0x5, x3, x1, 0          # veda.bind c3, 1  -> store STRIPPED
    li   x2, 0
    li   x6, 0xA5
    .insn r 0x0b, 0x3, 0x01, x6, x3, x2   # ocs.d through c3, offset 0
    mv   x17, x22                          # want (3<<5)|0x0C = 0x6C

    // leave both objects un-cowed
    li   x1, 1
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4
    li   x1, 104
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x21, mcause
    csrr x22, mtval
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
