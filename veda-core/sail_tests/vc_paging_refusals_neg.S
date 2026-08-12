.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 Phase 2, increment 2 -- WHAT THE PAIR REFUSES.
#
# Written because mutation testing found the first two paging tests proved
# the mechanism WORKS but almost nothing about what it REFUSES -- and for a
# security primitive that is where most of the value lives. Removing either
# gate below left all 82 tests passing.
#
# PART A -- PAGE-IN MUST REFUSE A LIVE, RESIDENT OBJECT. This is the
# security-critical one. Page-in preserves generation by design, which is
# what lets a paged-out object come back without killing its capabilities.
# Turned against a LIVE object, that same property becomes an attack: an
# authorized pager could repoint a live object's Base at memory of its
# choosing while every outstanding capability keeps validating, and nothing
# would signal the move. The contrast is exact -- doing the same thing with
# ODT-Populate BUMPS generation, which kills every capability and makes the
# relocation loud. The `not resident` half of the gate is the only thing
# standing between a pager and a silent, generation-invisible relocation.
#
# PART B -- PAGE-OUT MUST REFUSE AN ALREADY-PAGED-OUT OBJECT. A second
# page-out would bump generation again for no benefit, burning one of the
# 2^24 values the slot will ever have, and invalidating exactly the
# capabilities a pending page-in was about to serve.
#
# Both parts also assert the refusal did not HALF-APPLY: state a refused
# instruction leaves behind is worse than the refusal itself.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            # trap counter

    # ---- build a live, resident object at frame_old
    li   t1, 0x100
    slli t1, t1, 16
    ori  t1, t1, 0x000C                    # Length 0x100, Perms Load|Store
    csrw 0x7C4, t1
    la   t2, frame_old
    li   x1, 612
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # veda.odt.populate.fast

    li   x1, 612
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x00, x21, x0, x0   # cgetbase x21, c0 -- the live Base
    li   x2, 0
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0, x2, x3
    li   x22, 0x600D

    # ---- PART A: page-in a LIVE object at a different frame. MUST REFUSE.
    la   t2, frame_new
    li   x1, 612
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in -- must REFUSE
    li   t1, 1
    bne  x20, t1, fail                     # exactly one trap so far
    li   t1, 2
    bne  x23, t1, fail                     # mcause 2 = Illegal_Instruction
    li   x24, 0x600D

    # ---- A did not half-apply: the object must NOT have moved, and the
    #      capability held across it must still read what it stored.
    li   x1, 612
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, x1
    .insn r 0x5b, 0x0, 0x00, x25, x1, x0   # cgetbase x25, c1
    bne  x25, x21, fail                    # still at frame_old
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   # ocl.d c0, x2, x10 -- c0 still valid
    li   t1, 0xF00D
    bne  x10, t1, fail                     # generation untouched, data intact
    li   x26, 0x600D

    # ---- PART B: page out once (legal), then again (must refuse).
    li   x1, 612
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out -- must SUCCEED
    li   t1, 1
    bne  x20, t1, fail                     # still exactly one trap
    li   x27, 0x600D

    li   x1, 612
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out AGAIN -- REFUSE
    li   t1, 2
    bne  x20, t1, fail                     # now exactly two traps
    li   t1, 2
    bne  x23, t1, fail                     # mcause 2 again
    li   x28, 0x600D

    # ---- B did not half-apply: the object is still merely paged out, so a
    #      bind still reports RESIDENCY (0x0A) rather than anything else.
    li   x1, 612
    .insn i 0x0b, 0x5, x2, x1, 0           # veda.bind c2, x1 -- must trap 0x0A
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0x4A                          # (cap_idx 2 << 5) | cause 0x0A
    bne  x23, t1, fail
    li   x29, 0x600D

    li   t1, 0x600D
    bne  x22, t1, fail
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
    mv   x23, t5                           # ordinary trap: record mcause (2)
    j    resume
veda_trap_path:
    csrr x23, mtval                        # Veda trap: record the mtval word
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
frame_old:
    .zero 0x100
.balign 32
frame_new:
    .zero 0x100
