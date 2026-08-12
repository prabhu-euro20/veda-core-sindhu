.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R10 (DESIGN_07 Tier G) -- the rt_valid FAIL-CLOSED gate. The CRBR-load
# residency check (veda_region_rt_resident) must consult rt_valid BEFORE
# region_resident, so an UNCONFIGURED Region Table slot can never authorize
# a domain entry no matter what its resident bit contains.
#
# Region 3 is seeded in the contradictory state {rt_valid = false,
# region_resident = true} -- a slot never configured, whose resident bit is
# garbage. c14 is a region-3 SENTRY (Object_ID (3<<24)|1). OCReturn through
# it must REGION_FAULT, driven by rt_valid = false, EVEN THOUGH resident is
# true. A check that consulted only region_resident would wrongly admit it.
#
# rt_valid is dead code everywhere else in the model (set by seeds, read
# nowhere); the R10 fix is its first consumer, so this is the one test that
# keeps the conjunct honest.
#
# Expected: mcause 0x18, mtval = cap_idx<<5 | 0x09. cs1 = c14 ->
# mtval = (14<<5)|0x09 = 0x1C9.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    .insn r 0x5b, 0x1, 0x16, x0, x14, x0    # ocreturn c14  -- must REGION_FAULT (rt_valid=false)

    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x1C9                          # cap_idx 14 << 5 | 0x09
    bne  t3, t4, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
