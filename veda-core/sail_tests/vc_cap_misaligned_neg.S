.include "veda_selfcheck_macros.S"
.section .text
.global _start
# 32-byte natural alignment for OCL.C/OCS.C is architectural as of the
# 256-bit respec (DESIGN_01 decision 2), enforced as a HARD trap with its own
# cause (0x08). It is not decoration: it is the only rule under which "one
# capability occupies exactly one tag granule" is well-defined, and that
# invariant is what stops a plain store from tampering with half a stored
# capability while its tag survives (see vc_cap_granule_tamper_neg.S).
#
# offset 16 is deliberately chosen so the access is still fully IN BOUNDS
# (16 + 32 = 48 <= the object's 0x40 length) -- the trap must come from the
# alignment rule itself, not incidentally from a bounds violation.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1
    li   x2, 16
    .insn r 0x0b, 0x4, 0x01, x0, x0, x2  # ocs.c c0, x2(=16), c0 -- misaligned, must hard-trap
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x08         # cause=0x08 (Capability Misaligned), cap_idx=0 (c0)
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
