.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R10 (DESIGN_07 Tier G) -- OCInvoke into a NON-RESIDENT domain must raise
# an explicit VEDA_CAUSE_REGION_FAULT (0x09), never enter the compartment.
#
# This is the CALL half of the R10 escape closure. Before this fix the CRBR
# was reset-only, so a load at OCInvoke did not exist and a paged-out target
# domain would be entered blind. The fix loads the CRBR from the code
# capability's own Object_ID[43:24], validated RT-direct -- and refuses when
# that region is not resident.
#
# Fixture: c10 is a reset-seeded SEALED region-2 CODE capability
# (Object_ID (2<<24)|8, otype 0x0042, Perms Execute|Invoke), c11 the matching
# SEALED region-2 DATA (otype 0x0042, Invoke-only). Region 2 is seeded
# NON-RESIDENT (RT[2].region_resident = false). The pair passes ALL NINE of
# OCInvoke's capability checks -- tag, seal, matching otype, invoke on both,
# execute on code, non-execute on data -- so the FIRST and ONLY failure is
# the region gate. That isolation is the point: a test whose pair failed an
# earlier check would report REGION_FAULT for the wrong reason.
#
# Expected: mcause 0x18 (E_Extension), mtval = cap_idx<<5 | 0x09. cs1 = c10,
# so cap_idx = 10 -> mtval = (10<<5)|0x09 = 0x149.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # c10 (sealed region-2 CODE) and c11 (sealed region-2 DATA) come
    # straight from the reset seed -- no populate/bind/seal needed, because
    # a region-2 capability CANNOT be minted at runtime (Bind is
    # residency-gated), which is exactly the legal "held across a page-out"
    # state the seed models.
    .insn r 0x5b, 0x1, 0x12, x0, x10, x11  # ocinvoke c10, c11  -- must REGION_FAULT

    RVMODEL_HALT_FAIL                       # reached only if the invoke wrongly entered
.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x149                          # cap_idx 10 << 5 | 0x09
    bne  t3, t4, fail
    # The CRBR must NOT have moved: a faulting invoke commits nothing. The
    # region 0 default means an ordinary region-0 bind still resolves, which
    # the very next instruction proves by binding Object_ID 1 (region 0) and
    # reading back its seeded Base 0x80010000.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0            # veda.bind c0, x1  (region 0, must still work)
    .insn r 0x5b, 0x0, 0x00, x5, x0, x0     # cgetbase x5, c0
    li   t4, 0x80010000
    bne  x5, t4, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
