.include "veda_selfcheck_macros.S"
.section .text
.global _start
# TWO more census survivors closed, and the second one is a flaw in a test of
# my own.
#
# P1-P6 -- $veda_sealed survived its mutant on SIX of seven chains. Sealing is
# what makes a capability opaque: it can be passed around and it CANNOT be
# dereferenced. That is the basis of compartment entry sentries and of type
# authority, so a sealed capability that can still be read or written through
# is a hole straight through a compartment boundary. Six paths, one phase each.
#
# P7-P9 -- bounds as a TRAP DECISION on nmc_add.d, nmc_add.w and atomic.
# veda_smoke_check_order.S already drives those three through a Length-0
# capability and asserts BOUNDS, yet the bounds term survives its own mutant on
# all three. The reason is that in THAT test the object is also copy-on-write,
# so $veda_cow_write fires the trap and the cause chain -- where bounds
# correctly precedes cow -- still reports 0x01. The assertion holds for a reason
# the test did not intend: it verifies the cause ORDER and not the trap
# DECISION. Closing it needs a Length-0 capability to a NON-cow object, which
# nothing exercised. The census found this; no hand-written test could have.
#
# Objects are minted fresh, not seeded: the difftest showed all 16 capability
# registers diverge between the layers at reset.
#
# mtval is {cap_idx:5, cause:5}.
#   P1-P6 sealed  -> c3 with cause 0x03 = 0x63
#   P7-P9 bounds  -> c4 with cause 0x01 = 0x81
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0

    # object 10: the sealing AUTHORITY, Perms 0x0300 = Permit_Seal|Permit_Unseal
    li   x1, 10
    li   x2, 0x8001040000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 10
    .insn i 0x0b, 0x5, x2, x1, 0          # veda.bind c2, 10  -- the authority

    # object 20: the TARGET, Perms 0x100C = Load|Store|NMC_Compute, NOT cow
    li   x1, 20
    li   x2, 0x800102000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 20
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 20

    .insn r 0x5b, 0x1, 0x10, x3, x1, x2   # cseal c3, c1, c2  -- c3 is c1, sealed

    # ---------------- P1-P6: a sealed capability must never dereference ----------------
    li   x2, 0
    li   x6, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x6, x3, x2   # ocs.d
    mv   x10, x25
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x7, x3, x2   # ocl.d
    mv   x11, x25
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x3, x2   # ocs.c
    mv   x12, x25
    li   x2, 0
    .insn r 0x0b, 0x4, 0x00, x7, x3, x2   # ocl.c
    mv   x13, x25
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x7, x3, x2   # nmc_add.d
    mv   x14, x25
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x3, x2   # nmc_add.w
    mv   x15, x25

    # ---------------- P10: the ATOMIC path, sealed ----------------
    # ADDED AFTER THE CENSUS CAUGHT ITS ABSENCE. The first draft of this file
    # covered six paths for the sealed term -- but the six the census listed
    # were ocs, oclc, ocsc, nmc.w, nmc.d and ATOMIC, and I tested ocl (already
    # covered) instead of atomic. Eight of nine mutants died and atomic/sealed
    # survived, which is exactly the "applied to five of six" shape this
    # project has been bitten by three times. The census caught it in one run;
    # re-running it after adding a test is the step that makes that possible.
    li   x2, 0
    .insn r 0x2b, 0x3, 0x00, x7, x3, x2   # veda.amoadd.d through the sealed c3
    mv   x23, x25

    # ---------------- P7-P9: bounds must FIRE THE TRAP, not merely win the cause ----------------
    # c4 is Length 0 on a NON-cow object, so no other term can raise the trap.
    li   x2, 0
    .insn r 0x5b, 0x1, 0x08, x4, x1, x2   # csetbounds c4, c1, 0
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x7, x4, x2   # nmc_add.d
    mv   x16, x25
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x4, x2   # nmc_add.w
    mv   x17, x25
    li   x2, 0
    .insn r 0x2b, 0x3, 0x00, x7, x4, x2   # veda.amoadd.d
    mv   x18, x25

    # ---------------- CONTROL ----------------
    # The UNSEALED capability to the same object must still work, or every
    # phase above would also pass if the object were simply broken.
    li   x2, 0
    li   x6, 0x600D
    .insn r 0x0b, 0x3, 0x01, x6, x1, x2   # ocs.d through the unsealed c1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x19, x1, x2  # ocl.d -- must read 0x600D back
    mv   x21, x20                          # trap count must still be 9

    li   t1, 0x63
    bne  x10, t1, fail
    bne  x11, t1, fail
    bne  x12, t1, fail
    bne  x13, t1, fail
    bne  x14, t1, fail
    bne  x15, t1, fail
    bne  x23, t1, fail
    li   t1, 0x81
    bne  x16, t1, fail
    bne  x17, t1, fail
    bne  x18, t1, fail
    li   t1, 0x600D
    bne  x19, t1, fail
    li   t1, 10
    bne  x21, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
