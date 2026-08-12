.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 Phase 2, increment 2 -- THE FULL PAGING CYCLE, end to end.
#
# This is the test the mechanism exists for. Increment 1 built the fault;
# this builds the cycle that repairs it, and proves the cached-Base contract
# recorded in DESIGN_02 ("The cached-Base fork") actually holds:
#
#   bind -> use -> PAGE-OUT -> stale trap -> re-Bind -> PAGE-IN at a NEW
#   frame -> use succeeds AT THE NEW LOCATION
#
# Two real linker-allocated buffers give a genuine OLD frame and NEW frame,
# so "the object moved" is a fact about addresses, not a claim.
#
# WHY THE STALE TRAP ALONE PROVES NOTHING. Cause 0x02 fuses two conditions
# -- `not(entry.valid) | generation mismatch` -- so a page-out that merely
# DESTROYED the object would produce the identical 0x02. The follow-up bind
# is therefore mandatory, not decoration: a destroyed object binds 0x05
# (never existed), a paged-out one binds 0x0A (exists, absent). Asserting
# 0x0A is what distinguishes "paged out" from "destroyed".
#
# Object_ID 610 is used deliberately. The increment-1 fixture (600) is
# reset-seeded non-resident WITHOUT a generation bump and is paired with a
# live matching capability -- paging THAT in would revalidate a stale
# capability at a new Base. A seeded non-resident object is not a
# legitimate page-in input; the state must be PRODUCED by page-out, which is
# what makes this a live transition rather than a modelled one.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            # trap counter

    # ---- phase 1: create the object at the OLD frame, bind it, use it
    li   t1, 0x100                         # Length = 0x100, matching the frames
    slli t1, t1, 16
    ori  t1, t1, 0x000C                    # Perms = Load|Store
    csrw 0x7C4, t1                         # veda_attr
    la   t2, frame_old
    li   x1, 610
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # veda.odt.populate.fast

    li   x1, 610
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x00, x21, x0, x0   # cgetbase x21, c0  -- the OLD Base
    li   x2, 0
    li   x3, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0, x2, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   # ocl.d c0, x2, x10
    li   t1, 0xC0DE
    bne  x10, t1, fail
    li   x22, 0x600D                       # phase 1 ok

    # ---- phase 2: PAGE-OUT. Contents leave; generation bumps; the frame
    #      is free for someone else.
    li   x1, 610
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # veda.odt.page.out x5, x1

    # ---- phase 3: the held capability is now stale. Using it must trap
    #      0x02 -- NOT succeed, and NOT silently read the freed frame.
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   # ocl.d c0, x2, x10 -- must trap
    li   t1, 0x02
    bne  x23, t1, fail                     # mtval low bits = cause 0x02
    li   x24, 0x600D                       # phase 3 ok

    # ---- phase 4: re-Bind must report RESIDENCY (0x0A), not NOT-FOUND
    #      (0x05). This is what proves the object still EXISTS and was
    #      paged out, rather than destroyed.
    li   x1, 610
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1 -- must trap 0x0A
    li   t1, 0x0A
    bne  x23, t1, fail
    li   x25, 0x600D                       # phase 4 ok

    # ---- phase 5: PAGE-IN at a DIFFERENT frame.
    la   t2, frame_new
    li   x1, 610
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # veda.odt.page.in x5, x1, t2

    # ---- phase 6: re-Bind now succeeds, and hands back the NEW Base.
    li   x1, 610
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x00, x26, x0, x0   # cgetbase x26, c0  -- the NEW Base
    la   t1, frame_new
    bne  x26, t1, fail                     # it really moved
    beq  x21, x26, fail                    # OLD and NEW Base must DIFFER --
                                           # without this the test would pass
                                           # against a page-in that ignored
                                           # its Base operand entirely

    # ---- phase 7: the object works again, at the new location.
    li   x3, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0, x2, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   # ocl.d c0, x2, x10
    li   t1, 0xBEEF
    bne  x10, t1, fail
    li   x27, 0x600D                       # phase 7 ok

    # ---- final: exactly two traps (the stale use, and the re-Bind)
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x600D
    bne  x22, t1, fail
    bne  x24, t1, fail
    bne  x25, t1, fail
    bne  x27, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x23, mtval                        # cap_idx is c0 = 0, so mtval == cause
    addi x20, x20, 1
    csrr t3, mepc                          # resume PAST the faulting access
    addi t3, t3, 4
    csrw mepc, t3
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
