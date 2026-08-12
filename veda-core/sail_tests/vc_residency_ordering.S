.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 (Phase 2, increment 1) -- CHECK ORDER, which is the whole game.
#
# Adding `resident` makes several distinct conditions coincide on the same
# entry, and the causes must not blur. A never-populated slot is now BOTH
# invalid AND non-resident. A destroyed object is BOTH stale AND
# non-resident. If the residency term were placed before the validity term,
# each of those would start reporting 0x0A -- telling a pager to fetch an
# object that never existed, or to resurrect one that was deliberately
# revoked. Both would be silent, and both would be wrong.
#
# The invariant, stated positively: a RESIDENCY fault means the object
# EXISTS and is merely absent from memory. Not-found and destroyed are
# different, earlier, and NOT recoverable.
#
# This test pins that ordering from three directions in one run:
#   (A) never-populated  -> must stay 0x05 OBJECT_NOT_FOUND, not 0x0A
#   (B) genuinely absent -> 0x0A RESIDENCY_FAULT
#   (C) wrong-owner      -> must stay 0x06 OWNER_VIOLATION, not 0x0A
#
# (C) matters because the wrong-owner seed (Object_ID 5) is resident: if a
# residency check were ever placed before the owner check AND the seed were
# left non-resident, the access-control failure would be masked by a paging
# failure. Asserting it here keeps that ordering honest too.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                    # phase counter

    # ---- (A) never populated: Object_ID 601 is seeded nowhere at all.
    li   x1, 601
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1
    li   t0, 0x05
    bne  x21, t0, fail             # must be OBJECT_NOT_FOUND, NOT 0x0A

    # ---- (B) exists but paged out: Object_ID 600 is seeded resident=false.
    li   x1, 600
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1
    li   t0, 0x0A
    bne  x21, t0, fail             # must be RESIDENCY_FAULT

    # ---- (C) live, resident, but owned by another hart (seed 5, hart 0x63).
    li   x1, 5
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1
    li   t0, 0x06
    bne  x21, t0, fail             # must be OWNER_VIOLATION, NOT 0x0A

    li   t0, 3
    bne  x20, t0, fail             # exactly three traps fired
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x21, mtval                # low 5 bits are the cause (cap_idx = c0 = 0)
    addi x20, x20, 1
    csrr t3, mepc                  # resume past the faulting bind
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
