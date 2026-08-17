.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R38(b) -- WHAT PAGING DOES TO THE SPLIT RIGHT. MEASURED, NOT ARGUED.
    #
    # R38 gave the copy-on-write fault an eligibility predicate: the capability's
    # own PERM_STORE. Because veda.odt.set.cow deliberately does not bump the
    # generation, the capabilities that still carry store are exactly those minted
    # BEFORE the object became copy-on-write -- so the split right belongs to
    # whoever held write authority at that moment, and a later binder gets a read
    # capability because veda_bind_perms masks with 0xFFF7.
    #
    # THE SPLIT RIGHT THEREFORE LIVES ONLY INSIDE LIVE CAPABILITY REGISTERS, and
    # this machine has a privileged primitive whose declared job is to invalidate
    # every live capability while leaving the entry's policy fields alone:
    #     veda.odt.page.out -- generation = old_entry.generation + 1
    #                          cow        = old_entry.cow
    # After one paging round trip every pre-cow capability is stale, `cow` is
    # still set, and the only way to obtain a capability is a Bind that strips
    # store. NOBODY ON THE MACHINE CAN SPLIT THE OBJECT ANY MORE.
    #
    # This test exists because that was an ARGUMENT and arguments are not
    # measurements. It pins the behaviour so the interaction cannot drift while
    # it is decided, exactly as R36's own test did for the privilege model.
    # Plain veda.odt.populate reproduces it without paging at all -- it bumps the
    # generation on a still-valid slot and carries cow across unchanged.
    #
    # IT IS FAIL-CLOSED, WHICH IS WHY IT IS RECORDED RATHER THAN PATCHED IN A
    # HURRY: the lockout DENIES a write, it never grants one, and phase 5 shows
    # privileged software can still release the object by clearing cow -- giving
    # up the sharing rather than the write. The leading closure is to make
    # page-out REFUSE on a copy-on-write object, and its real cost has to be
    # stated with it: copy-on-write pages become unpageable, and in a real system
    # those are the common case.
    #
    #   x21  phase 1 -- the entitled pre-cow holder really does split (0x0C)
    #   x22  phase 3 -- after paging its capability is stale (0x02)
    #   x23  phase 4 -- THE LOCKOUT: the only obtainable capability is refused
    #                   0x13, and no capability on the machine can reach 0x0C
    #   x24  phase 5 -- privileged software can still release the object
    #   x20  traps -- exactly 3
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x25, 0

    li   t1, 0x100
    slli t1, t1, 16
    ori  t1, t1, 0x000C                    # Length 0x100, Perms Load|Store
    csrw 0x7C4, t1
    la   t2, frame_a
    li   x1, 750
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # populate.fast 750 at frame_a

    li   x1, 750
    .insn i 0x0b, 0x5, x0, x1, 0           # bind c0 -- BEFORE cow, so it keeps store

    li   x1, 750
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4    # veda.odt.set.cow 750 <- 1

    # ---- phase 1: the entitled holder asks for its copy
    li   x2, 0
    li   x3, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0 -- COW fault
    li   t1, 0x0C                          # (c0 << 5) | 0x0C
    bne  x25, t1, fail
    li   t1, 1
    bne  x20, t1, fail
    li   x21, 0x600D

    # ---- phase 2: page out and back in at a DIFFERENT frame
    li   x1, 750
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- bumps generation, keeps cow
    la   t2, frame_b
    li   x1, 750
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2    # page.in at the new frame

    # ---- phase 3: the pre-cow capability died with the generation bump
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    # ocs.d c0 -- Tag violation
    li   t1, 0x02                          # (c0 << 5) | 0x02
    bne  x25, t1, fail
    li   t1, 2
    bne  x20, t1, fail
    li   x22, 0x600D

    # ---- phase 4: THE LOCKOUT
    li   x1, 750
    .insn i 0x0b, 0x5, x1, x1, 0           # bind c1, 750 -- the only way back in
    .insn r 0x5b, 0x0, 0x02, x11, x1, x0   # cgetperm c1
    andi x12, x11, 8                       # bit 3 = Permit_Store
    bnez x12, fail                         # the mask really did strip it
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2    # ocs.d c1 -- refused, not repaired
    li   t1, 0x33                          # (c1 << 5) | 0x13 PERM_STORE
    bne  x25, t1, fail
    li   t1, 3
    bne  x20, t1, fail
    li   x23, 0x600D

    # ---- phase 5: the recovery that exists today. Privileged software gives up
    #      the sharing rather than the write.
    li   x1, 750
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4    # veda.odt.set.cow 750 <- 0
    li   x1, 750
    .insn i 0x0b, 0x5, x2, x1, 0           # bind c2 -- no longer masked
    li   x2, 0
    .insn r 0x0b, 0x3, 0x01, x3, x2, x2    # ocs.d c2 -- must SUCCEED
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x2, x2   # ocl.d c2 -- read it back
    li   t1, 0xC0DE
    bne  x10, t1, fail
    li   t1, 3
    bne  x20, t1, fail                     # and it took no further trap
    li   x24, 0x600D

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi x20, x20, 1
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x25, mtval
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
