.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R38(b) -- A COPY-ON-WRITE OBJECT IS NOT PAGEABLE, AND THAT IS THE FIX.
    #
    # This file replaces vc_r38_cow_paging_lockout.S, which MEASURED the defect and
    # is renamed rather than edited because its name became wrong: there is no
    # lockout any more.
    #
    # THE DEFECT. R38 made the split right belong to whoever held PERM_STORE when
    # the object became copy-on-write. set.cow deliberately does not bump the
    # generation, so that entitlement lives in exactly one place -- the live
    # capabilities that predate it. veda.odt.page.out exists to destroy exactly
    # those: it bumps the generation, which is how outstanding capabilities are
    # invalidated and is necessary because every capability caches its own Base.
    # It also carried `cow` across untouched. One round trip therefore left an
    # object NOBODY could split: every pre-cow capability stale, the entry still
    # copy-on-write, and the only way back in a Bind that masks store off.
    #
    # THE "RECOVERY" THAT LOOKED AVAILABLE WAS UNSAFE, and the earlier version of
    # this test recorded it as though it were a way out. Clearing `cow` on a
    # genuinely shared object lets EVERY sharer write THE SAME object -- exactly
    # the isolation copy-on-write was providing. A recovery that silently merges
    # two writers is worse than the lockout it repairs.
    #
    # THE FIX IS AT THE INSTRUCTION THAT DESTROYS THE EVIDENCE, not a repair
    # attempted afterwards from state that no longer exists. page.out now refuses
    # on a copy-on-write object. The cost is real and is stated rather than hidden:
    # a shared object cannot be evicted until the sharing resolves. It cannot be
    # weaponised -- page.out and set.cow both require Machine or ODA authority.
    #
    #   x21  the entitled pre-cow holder still splits          -- mtval 0x0C
    #   x22  page.out on the copy-on-write object is REFUSED   -- mcause 0x02
    #   x23  and BECAUSE it was refused the entitlement survives: the same
    #        capability splits again. This is the whole point of the increment.
    #   x24  CONTROL: a NON-cow object still pages out and back in cleanly, so the
    #        refusal is a policy about copy-on-write and not a broken page.out
    #   x25  once the sharing is resolved, the object pages out normally
    #   x20  traps -- exactly 3
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x18, 0                            # last mcause
    li   x19, 0                            # last mtval

    li   t1, 0x100
    slli t1, t1, 16
    ori  t1, t1, 0x000C                    # Length 0x100, Perms Load|Store
    csrw 0x7C4, t1
    la   t2, frame_a
    li   x1, 750
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # populate.fast 750

    li   x1, 750
    .insn i 0x0b, 0x5, x0, x1, 0           # bind c0 BEFORE cow -- it keeps store
    li   x1, 750
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4    # veda.odt.set.cow 750 <- 1

    # ---- phase 1: the entitled holder asks for its copy
    li   x2, 0
    li   x3, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0 -- COW fault
    li   t1, 0x18
    bne  x18, t1, fail
    li   t1, 0x0C
    bne  x19, t1, fail
    li   t1, 1
    bne  x20, t1, fail
    li   x21, 0x600D

    # ---- phase 2: page-out must REFUSE, and it is an illegal instruction
    li   x1, 750
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- REFUSED
    li   t1, 0x02
    bne  x18, t1, fail
    li   t1, 2
    bne  x20, t1, fail
    li   x22, 0x600D

    # ---- phase 3: the entitlement survived, because nothing destroyed it
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0 -- COW fault AGAIN
    li   t1, 0x18
    bne  x18, t1, fail
    li   t1, 0x0C
    bne  x19, t1, fail
    li   t1, 3
    bne  x20, t1, fail
    li   x23, 0x600D

    # ---- phase 4: CONTROL. A non-cow object pages out and back in cleanly.
    la   t2, frame_b
    li   x1, 751
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # populate.fast 751 -- NOT cow
    li   x1, 751
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- must SUCCEED
    la   t2, frame_b
    li   x1, 751
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # page.in  -- must SUCCEED
    li   t1, 3
    bne  x20, t1, fail                     # no new trap
    li   x24, 0x600D

    # ---- phase 5: resolve the sharing, and the object becomes pageable again
    li   x1, 750
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4    # veda.odt.set.cow 750 <- 0
    li   x1, 750
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- now allowed
    li   t1, 3
    bne  x20, t1, fail
    li   x25, 0x600D

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi x20, x20, 1
    csrr x18, mcause
    csrr x19, mtval
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

.section .data
.balign 32
frame_a:
    .zero 0x100
.balign 32
frame_b:
    .zero 0x100
