.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R62 (D6) -- veda.odt.set.domain wrote an unvalidated principal.
#
# The value came straight from rs2[19..0] into owner_domain with no check of
# any kind. The refusal it needed was already in the same function, three lines
# above, written for the object half: a policy on a slot that holds nothing is
# refused because "allowing it would let software pre-stage rules on slots it
# does not own yet, to take effect when someone else populates them."
#
# The domain half is the stronger case. A domain IS a region (R10), so a policy
# naming an UNCONFIGURED region takes effect when someone else is GIVEN that
# region -- authority that OUTLIVES ITS AUTHOR. An early-boot component with a
# delegated ODA can stamp a future principal and then be dismissed; dropping its
# ODA unstamps nothing.
#
# Region 3 is the perfect fixture and it already exists: R10 seeded it
# {rt_valid = false, region_resident = true} precisely so a check that reads the
# wrong bit cannot pass. Naming it must be refused even though it looks resident.
#
# The check is at WRITE time, and that is the whole finding: a read-time check in
# veda_bind_domain_ok would make the object unbindable while the region is
# unconfigured and bindable the moment it is configured -- the attack, arriving
# on schedule.
#
# Object 130 is minted here; nothing seeds it.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0                             # trap counter. NOT x29: t4 IS x29,
                                            # and comparing the counter against
                                            # itself made every count assertion
                                            # below vacuous in the first draft.
    li   x26, 0                             # last mtval

    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C                     # Len 0x20, Perms Load|Store
    or   x2, x6, x7
    li   x1, 130
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # veda.odt.populate 130
    bne  x27, x0, fail                      # the populate must not trap

    # CONTROL 1 -- a REAL principal is accepted. Region 1 is configured and
    # resident. Without this a machine that refused every set.domain would pass.
    li   x1, 130
    li   x4, 1
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4     # veda.odt.set.domain 130 -> 1
    bne  x27, x0, fail
    li   x20, 0x600D

    # CONTROL 2 -- so is the open sentinel. VEDA_DOMAIN_ANY is not a principal,
    # it is the ABSENCE of a restriction, and it is what R41 and R58 reset the
    # field to -- so gating it would have broken object destruction.
    li   x1, 130
    li   x4, 0xFFFFF
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4     # veda.odt.set.domain 130 -> ANY
    bne  x27, x0, fail
    li   x21, 0x600D

    # THE FINDING -- region 3 has never been configured. rt_valid = false while
    # region_resident = true, so this also proves the check reads rt_valid and
    # not the residency bit beside it.
    li   x1, 130
    li   x4, 3
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4     # veda.odt.set.domain 130 -> 3
    li   t4, 1
    bne  x27, t4, fail                      # exactly one trap
    li   x22, 0x600D

    # AND an out-of-window domain, which no region table entry can ever back.
    li   x1, 130
    li   x4, 0x3FF
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   t4, 2
    bne  x27, t4, fail
    li   x23, 0x600D

    # CONTROL 3 -- and after two refusals the field still holds what CONTROL 2
    # left there, so a refused write wrote NOTHING. A bind from the ambient
    # context must still succeed: owner_domain is still VEDA_DOMAIN_ANY, not 3.
    li   x1, 130
    .insn i 0x0b, 0x5, x3, x1, 0            # veda.bind c3, 130
    li   t4, 2
    bne  x27, t4, fail                      # no new trap
    .insn r 0x5b, 0x0, 0x03, x24, x3, x0    # cgettag x24, c3
    li   t4, 1
    bne  x24, t4, fail                      # and it really minted

    li   t4, 0x600D
    bne  x20, t4, fail
    bne  x21, t4, fail
    bne  x22, t4, fail
    bne  x23, t4, fail
    RVMODEL_HALT_PASS
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
.section .data
.balign 32
arena:
    .space 32
