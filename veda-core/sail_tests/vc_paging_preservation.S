.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 Phase 2, increment 2 -- WHAT PAGE-IN PRESERVES.
#
# Written because mutation testing showed both preservation properties were
# untested: making page-in bump generation, or reset owner_hart, left all 82
# tests passing. Preservation is the entire reason page-in is a separate
# instruction rather than a Populate, so leaving it unverified would have
# meant the increment's central claim rested on nothing.
#
# PART A -- GENERATION IS PRESERVED, measured by counting.
# `generation` is architecturally unreadable by design (there is no CGet for
# it), so it is observed indirectly through the saturation refusal: page-out
# refuses once generation reaches the 0xFFFFFF ceiling. Object_ID 614 is
# seeded at 0xFFFFFD, TWO steps below, and the count of successful page-outs
# before the refusal is the discriminator:
#     preserving -- FD->FE, FE->FF, then refused  = TWO succeed
#     bumping    -- FD->FE, page-in bumps to FF   = ONE succeeds
# A fixture one step below would NOT discriminate: a wrong bump would
# saturate to 0xFFFFFF, which looks identical to correct preservation. The
# mutation hides in the saturation, which is exactly why the fixture is at
# FD and not FE.
#
# PART B -- owner_hart IS PRESERVED.
# Page-out is gated on ODA authority, NOT on ownership, so a pager may
# legitimately evict an object it does not own. If page-in then reset
# owner_hart to unowned -- which is precisely what using Populate as page-in
# would do -- any hart could claim that object afterwards. That is object
# theft by triggering a page fault. Object_ID 615 is seeded live, resident,
# and owned by hart 99, so Bind's own 0x06 refusal makes the ownership
# observable in a single-hart model.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            # trap counter

    # ═══ PART A: generation preservation, by counting page-outs ═══
    # page-out #1 on Object_ID 614 (generation 0xFFFFFD) -- must SUCCEED
    li   x1, 614
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out
    li   t1, 0
    bne  x20, t1, fail                     # no trap
    li   x21, 0x600D

    la   t2, frame_a
    li   x1, 614
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in -- must SUCCEED
    bne  x20, t1, fail                     # still no trap
    li   x22, 0x600D

    # page-out #2 -- must SUCCEED if page-in PRESERVED generation (it is
    # 0xFFFFFE now, one below the ceiling). Under a page-in that bumped, the
    # generation would already be 0xFFFFFF and this would be REFUSED.
    li   x1, 614
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out
    li   t1, 0
    bne  x20, t1, fail                     # THE ASSERTION: still no trap
    li   x23, 0x600D

    la   t2, frame_b
    li   x1, 614
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in -- must SUCCEED
    bne  x20, t1, fail
    li   x24, 0x600D

    # page-out #3 -- NOW it must refuse: generation reached the ceiling.
    # This pins the count at exactly two, so the test cannot pass by the
    # refusal simply never happening.
    li   x1, 614
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out -- must REFUSE
    li   t1, 1
    bne  x20, t1, fail
    li   t1, 2
    bne  x25, t1, fail                     # mcause 2 = Illegal_Instruction
    li   x26, 0x600D

    # ═══ PART B: owner_hart preservation ═══
    # precondition: Object_ID 615 is owned by hart 99, so bind refuses 0x06
    li   x1, 615
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1 -- must trap 0x06
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x06
    bne  x25, t1, fail                     # cap_idx c0 = 0, so mtval == cause
    li   x27, 0x600D

    # a full paging cycle on an object this hart does not own
    li   x1, 615
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out -- allowed (ODA)
    la   t2, frame_c
    li   x1, 615
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in
    li   t1, 2
    bne  x20, t1, fail                     # neither trapped
    li   x28, 0x600D

    # THE ASSERTION: ownership survived, so bind must STILL refuse 0x06.
    # If page-in had reset owner_hart, this bind would SUCCEED -- the object
    # would have been stolen by paging it.
    li   x1, 615
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1 -- must trap 0x06
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0x06
    bne  x25, t1, fail
    li   x29, 0x600D

    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x24, t1, fail
    bne  x26, t1, fail
    bne  x27, t1, fail
    bne  x28, t1, fail
    bne  x29, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t5, mcause
    li   t6, 0x18
    beq  t5, t6, veda_trap_path
    mv   x25, t5                           # ordinary trap: mcause (2)
    j    resume
veda_trap_path:
    csrr x25, mtval                        # Veda trap: the mtval word
resume:
    addi x20, x20, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
frame_a:
    .zero 0x100
.balign 32
frame_b:
    .zero 0x100
.balign 32
frame_c:
    .zero 0x100
