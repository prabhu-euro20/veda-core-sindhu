.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # A sealed capability's rights are frozen: CAndPerm on a sealed source
    # must soft-fail (write the fields but clear the Tag), never yield a
    # usable, differently-permissioned sealed capability.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0        # veda.bind c0, x1  (tagged, unsealed)
    .insn r 0x5b, 0x1, 0x15, x1, x0, x0  # csealentry c1, c0  (seal with SENTRY otype)
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0 # cgettag x10, c1
    li   x20, 1
    bne  x10, x20, fail                  # sanity: csealentry produced a valid sealed cap

    # Attenuate the SEALED cap -> soft-fail path.
    li   x3, 0x0008
    .insn r 0x5b, 0x1, 0x17, x2, x1, x3  # candperm c2, c1, x3
    .insn r 0x5b, 0x0, 0x03, x12, x2, x0 # cgettag x12, c2
    bne  x12, x0, fail                   # KEY: sealed source => result Tag == 0

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
