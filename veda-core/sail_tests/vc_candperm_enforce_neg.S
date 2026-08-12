.include "veda_selfcheck_macros.S"
.section .text
.global _start
# CAndPerm rights attenuation, ENFORCED -- closing a real pre-existing gap.
#
# Before this test, the corpus exercised CAndPerm only as a METADATA
# operation: vc_candperm.S strips every permission and then inspects the
# result with cgetperm/cgettag, and vc_candperm_neg.S checks the sealed-source
# soft-fail. Neither ever attempts an ACCESS with an attenuated capability
# (verified: zero ocs.d in either file). So nothing anywhere proved that
# removing a right actually BLOCKS anything -- attenuation was tested as
# bookkeeping, never as enforcement.
#
# Consequently VEDA_CAUSE_PERM_LOAD_VIOLATION (0x12) and
# VEDA_CAUSE_PERM_STORE_VIOLATION (0x13) had ZERO coverage across all 79
# tests, despite both being implemented in veda_check_access. That matters
# beyond tidiness: DESIGN_02's copy-on-write mechanism plans to reuse the
# store-side path as its COW fault, so it would have been built on a trap no
# test had ever fired.
#
# Object_ID 1 is seeded Perms 0x100C = Permit_Load (bit 2) | Permit_Store
# (bit 3) | Permit_NMC_Compute (bit 12).
#
# Four phases, and phases 3 and 5 are the ones that make this a real test
# rather than a pair of trap assertions: they prove the attenuation is
# PRECISE -- it removes exactly the named right and leaves the other intact.
# A blanket "capability is now useless" implementation would pass phases 2
# and 4 and fail these.
#
#   1. full capability c0 -- store then load round-trips (positive control,
#      so a later failure cannot be blamed on the object or the setup)
#   2. c1 = c0 with Permit_Store cleared -- ocs.d must trap 0x13
#      mtval = (1 << 5) | 0x13 = 0x33
#   3. c1 must STILL load, and must still read the ORIGINAL value -- which
#      also proves the refused store never landed
#   4. c4 = c0 with Permit_Load cleared -- ocl.d must trap 0x12
#      mtval = (4 << 5) | 0x12 = 0x92
#   5. c4 must STILL store
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                    # trap counter

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1 -- full Perms 0x100C

    # ---- phase 1: positive control, full capability round-trips
    li   x2, 0                     # offset
    li   x3, 0xABC
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d c0, x2, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d c0, x2, x10
    li   x6, 0xABC
    bne  x10, x6, fail
    li   x22, 0x600D

    # ---- phase 2: strip Permit_Store (bit 3) -> c1, then try to store
    li   x6, 0xFFF7                # mask: clear bit 3, keep everything else
    .insn r 0x5b, 0x1, 0x17, x1, x0, x6   # candperm c1, c0, x6
    li   x3, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2   # ocs.d c1, x2, x3 -- must trap 0x13
    mv   x23, x21                  # mtval from that trap -- expect 0x33

    # ---- phase 3: c1 must STILL load, and read the ORIGINAL value.
    # Two things at once: attenuation removed only the store right, and the
    # refused store genuinely never reached memory.
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x1, x2  # ocl.d c1, x2, x10
    li   x6, 0xABC
    bne  x10, x6, fail             # 0xDEAD here would mean the store landed
    li   x24, 0x600D

    # ---- phase 4: strip Permit_Load (bit 2) -> c4, then try to load
    li   x6, 0xFFFB                # mask: clear bit 2
    .insn r 0x5b, 0x1, 0x17, x4, x0, x6   # candperm c4, c0, x6
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x4, x2  # ocl.d c4, x2, x10 -- must trap 0x12
    mv   x25, x21                  # mtval from that trap -- expect 0x92

    # ---- phase 5: c4 must STILL store (attenuation is precise both ways).
    # Verified through the FULL capability c0, since c4 cannot read it back.
    li   x3, 0x5A5A
    .insn r 0x0b, 0x3, 0x01, x3, x4, x2   # ocs.d c4, x2, x3 -- must SUCCEED
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d c0, x2, x10
    li   x6, 0x5A5A
    bne  x10, x6, fail
    li   x26, 0x600D

    # ---- final checks
    li   x6, 0x33
    bne  x23, x6, fail             # store violation reported 0x13 with cap_idx 1
    li   x6, 0x92
    bne  x25, x6, fail             # load violation reported 0x12 with cap_idx 4
    li   x6, 2
    bne  x20, x6, fail             # exactly two traps, no more, no fewer
    li   x6, 0x600D
    bne  x22, x6, fail
    bne  x24, x6, fail
    bne  x26, x6, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18                  # E_Extension -- every Veda hard trap
    bne  t3, t4, fail
    csrr x21, mtval
    addi x20, x20, 1
    csrr t3, mepc                  # resume past the refused access
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
