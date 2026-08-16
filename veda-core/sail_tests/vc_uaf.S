.include "veda_selfcheck_macros.S"
.section .text
.global _start
# TEMPORAL SAFETY -- use-after-free, on every dereference path.
#
# The RTL mutation census removed $veda_gen_stale from each of the seven
# dereference violation expressions and found it SURVIVES ON SIX OF SEVEN: the
# entire use-after-free defence could be deleted from six paths and all 82 RTL
# tests stayed green. This is the Sail half of closing that.
#
# THE CONSTRUCTION IS THE POINT. The generation check subsumes validity, so
# merely destroying an object proves only that an invalid entry is refused --
# something a plain validity check would also catch. The half that matters for
# temporal safety is the other one: the object is freed, THE SLOT IS REUSED,
# the entry is valid again, and an old capability must not reach the new
# occupant.
#
# So this destroys AND re-populates. Afterwards the stale capability is tagged,
# unsealed, permitted, in bounds and resident -- every other check passes -- and
# ONLY the generation differs. Nothing but the generation comparison can refuse
# it, which makes this a single-term discriminator rather than a test that
# happens to trap.
#
# Object 20 is minted fresh rather than reusing a seeded fixture, because the
# cross-layer difftest has shown the two layers disagree about all 16 capability
# registers at reset. A temporal-safety test built on a seeded fixture would
# inherit that divergence.
#
# Six phases -- OCS.D, OCL.D, OCS.C, OCL.C, NMC_ADD.D, NMC_ADD.W -- each
# expecting mtval {cap_idx:5, cause:5} = (1<<5)|0x02 = 0x22, plus a control
# proving a FRESH bind to the same object still works.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0

    li   x1, 20
    li   x2, 0x800102000040100C          # Base=0x80010200 Length=0x40 Perms=0x100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate 20

    li   x1, 20
    .insn i 0x0b, 0x5, x1, x1, 0         # veda.bind c1, 20

    li   x1, 20
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy 20  (bumps generation)
    li   x1, 20
    li   x2, 0x800102000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate 20  (SAME SLOT reused)

    li   x2, 0
    li   x3, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d through the stale c1
    mv   x10, x25
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x4, x1, x2  # ocl.d
    mv   x11, x25
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x1, x2  # ocs.c
    mv   x12, x25
    li   x2, 0
    .insn r 0x0b, 0x4, 0x00, x6, x1, x2  # ocl.c
    mv   x13, x25
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x7, x1, x2  # nmc_add.d
    mv   x14, x25
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x1, x2  # nmc_add.w
    mv   x15, x25

    # control: a FRESH bind to the very same object must still work, or the six
    # phases above would also pass if the object were simply broken.
    li   x1, 20
    .insn i 0x0b, 0x5, x8, x1, 0         # veda.bind c8, 20
    li   x2, 0
    li   x3, 0x600D
    .insn r 0x0b, 0x3, 0x01, x3, x8, x2  # must SUCCEED
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x16, x8, x2 # must read 0x600D back
    mv   x17, x20

    li   t1, 0x22
    bne  x10, t1, fail
    bne  x11, t1, fail
    bne  x12, t1, fail
    bne  x13, t1, fail
    bne  x14, t1, fail
    bne  x15, t1, fail
    li   t1, 0x600D
    bne  x16, t1, fail
    li   t1, 6
    bne  x17, t1, fail
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
