.include "veda_selfcheck_macros.S"
.section .text
.global _start
# The wall actually falling. Under the old format Length was 16 bits, so an
# object could not exceed 65535 bytes -- not "was not allowed to", could not
# be EXPRESSED. This test creates an object of 0x20000 bytes (128 KiB, twice
# the old ceiling) through the wide populate path and accesses a byte beyond
# the old limit, which is only reachable because the ODT entry itself now
# carries a 40-bit Length.
#
# Wide path = veda.odt.populate.fast: Base comes from a GPR at its full
# width, Length/Perms come from veda_attr (now 64-bit, Length[55:16] |
# Perms[15:0]). The compact single-GPR descriptor form cannot express this --
# 56+40+16 bits do not fit one register -- which is exactly why the fast form
# is the wide one.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # veda_attr = Length 0x20000 (128 KiB) in [55:16], Perms 0x000C in [15:0].
    li   t1, 0x20000
    slli t1, t1, 16
    ori  t1, t1, 0x000C
    csrw 0x7C4, t1

    la   t2, g_big                       # Base, full width from a GPR
    li   a0, 7
    .insn r 0x0b, 0x0, 0x04, x5, a0, t2  # veda.odt.populate.fast x5, a0, t2
    li   a0, 7
    .insn i 0x0b, 0x5, x0, a0, 0         # veda.bind c0, a0

    # Length must read back as the full 0x20000 -- proof the ODT carried it.
    .insn r 0x5b, 0x0, 0x01, x10, x0, x0 # cgetlen x10, c0
    li   x20, 0x20000
    bne  x10, x20, fail

    # Store and reload at offset 0x18000 -- far beyond the old 0xFFFF ceiling.
    # Under the previous format this offset was unrepresentable, so this access
    # could not have been attempted at all, let alone bounds-checked correctly.
    li   x3, 0x18000
    li   x4, 0x5EED
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3, x4
    .insn r 0x0b, 0x3, 0x00, x11, x0, x3 # ocl.d x11, c0, x3
    bne  x11, x4, fail

    # The bound is still enforced at the new, larger limit: offset 0x20000 is
    # one byte past the end and must hard-trap. A widened field is only
    # meaningful if the check widened with it.
    li   x3, 0x20000
    .insn r 0x0b, 0x3, 0x00, x12, x0, x3 # ocl.d x12, c0, x3 -- must trap
    j    fail

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail_h
    csrr t3, mtval
    li   t4, 0x01                        # cause 0x01 (Bounds Violation), cap_idx 0
    bne  t3, t4, fail_h
    RVMODEL_HALT_PASS
fail_h:
    RVMODEL_HALT_FAIL
fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
g_big:
    .zero 0x20000
