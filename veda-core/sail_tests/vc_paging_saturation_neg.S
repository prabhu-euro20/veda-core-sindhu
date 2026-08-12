.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 Phase 2, increment 2 -- THE SATURATION REFUSAL.
#
# This is the security core of the increment, and it guards a hole that is
# reachable rather than theoretical.
#
# THE HOLE. The whole safety argument for paging rests on one thing: PAGE-OUT
# bumps `generation`, which invalidates every outstanding capability, so a
# holder cannot keep using its CACHED Base after the object moves. But
# `generation` SATURATES at 0xffffff rather than wrapping. At saturation the
# bump would be a silent no-op -- page-out would clear residency while
# invalidating NOTHING -- and the following PAGE-IN, which preserves
# generation by design, would restore residency at a NEW frame while every
# outstanding capability still matched. Each would then compute its address
# from its own stale cached Base and read and write the FREED frame, now
# owned by another object. A full use-after-free: exactly the attack the
# pair exists to prevent, reappearing at the boundary.
#
# `retired` does not intercept it. A Destroy from 0xfffffe leaves generation
# 0xffffff with retired STILL false (its rule tests the OLD generation), and
# a following Populate is then permitted and leaves the slot valid, resident,
# saturated and un-retired -- precisely the state that breaks the contract.
# This test drives exactly that sequence, so the fixture is the real
# reachable state and not a hand-placed one.
#
# THE FIX UNDER TEST: page-out refuses (Illegal_Instruction, mcause 2) once
# generation is saturated. If the invalidation mechanism cannot run, the
# operation that depends on it must not proceed. Fail closed. The cost is
# that a pager cannot evict one exhausted object; the alternative cost is the
# temporal-safety guarantee of the whole design.
#
# Object_ID 611, seeded nowhere, built to the boundary here at runtime.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            # trap counter

    # ---- build an object whose generation is one step below saturation.
    # Populate bumps only when the old entry was valid, so a fresh slot
    # keeps generation 0. Drive it up with populate/destroy pairs would take
    # 2^24 iterations -- instead use the same near-boundary seed technique
    # the corpus already uses, via the dedicated fixture object 611 seeded
    # at 0xFFFFFE (see veda_test_seed_odt).
    #
    # Sanity: 611 is live and resident, so page-out is legal right now.
    li   x1, 611
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1 -- must succeed
    .insn r 0x5b, 0x0, 0x03, x21, x0, x0   # cgettag x21, c0 -- expect 1
    li   t1, 1
    bne  x21, t1, fail
    li   x22, 0x600D

    # ---- page-out #1: generation 0xFFFFFE -> 0xFFFFFF. Legal: the bump
    #      still genuinely invalidates.
    li   x1, 611
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out -- must SUCCEED
    li   t1, 0
    bne  x20, t1, fail                     # no trap yet
    li   x23, 0x600D

    # ---- page it back in so it is resident again, generation still
    #      0xFFFFFF (preserved -- that is page-in's contract).
    la   t2, frame_a
    li   x1, 611
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in -- must SUCCEED
    bne  x20, t1, fail                     # still no trap
    li   x24, 0x600D

    # ---- page-out #2: THE ASSERTION. Generation is saturated, so the bump
    #      would invalidate nothing. Page-out must REFUSE rather than clear
    #      residency on a promise it cannot keep.
    li   x1, 611
sat_instr:
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out -- must REFUSE
    li   t1, 1
    bne  x20, t1, fail                     # exactly one trap fired
    li   t1, 2
    bne  x25, t1, fail                     # mcause 2 = Illegal_Instruction
    li   x26, 0x600D

    # ---- and the object must still be USABLE: a refused page-out must not
    #      have half-applied. It stays resident, so a bind still works.
    li   x1, 611
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, x1 -- must succeed
    .insn r 0x5b, 0x0, 0x03, x27, x1, x0   # cgettag x27, c1 -- expect 1
    li   t1, 1
    bne  x27, t1, fail
    .insn r 0x5b, 0x0, 0x00, x28, x1, x0   # cgetbase x28, c1
    la   t1, frame_a
    bne  x28, t1, fail                     # still at the frame page-in gave it
    li   x29, 0x600D

    li   t1, 0x600D
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x24, t1, fail
    bne  x26, t1, fail
    bne  x29, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr x25, mcause                       # Illegal_Instruction = 2, not 0x18
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
frame_a:
    .zero 0x100
