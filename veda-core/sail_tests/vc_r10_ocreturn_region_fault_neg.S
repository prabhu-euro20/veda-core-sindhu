.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R10 (DESIGN_07 Tier G) -- OCReturn into a NON-RESIDENT domain must raise
# an explicit VEDA_CAUSE_REGION_FAULT (0x09), never re-enter the caller.
#
# This is the RETURN half, and the sharper half of the escape closure. The
# original R10 hole was precisely that OCReturn restored no region: a caller
# returning from a callee kept the callee's region as "current", which is
# fault-exempt by construction. The fix derives the returned-to domain from
# the SENTRY's own Object_ID[43:24] and validates it RT-direct, refusing a
# return into a since-paged-out caller domain.
#
# Fixture: c13 is a reset-seeded region-2 SENTRY (Object_ID (2<<24)|10,
# otype 0xFFFE = VEDA_OTYPE_SENTRY, Perms Execute). It passes OCReturn's four
# checks -- tag, sealed, sentry otype, execute -- so the region gate is again
# the sole failure.
#
# Expected: mcause 0x18, mtval = cap_idx<<5 | 0x09. cs1 = c13, so
# cap_idx = 13 -> mtval = (13<<5)|0x09 = 0x1A9.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    .insn r 0x5b, 0x1, 0x16, x0, x13, x0    # ocreturn c13  -- must REGION_FAULT

    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x1A9                          # cap_idx 13 << 5 | 0x09
    bne  t3, t4, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
