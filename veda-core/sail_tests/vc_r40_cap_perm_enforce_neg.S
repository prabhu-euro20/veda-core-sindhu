.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R40 -- CAN A "DATA ONLY" DELEGATION BE USED TO LIFT AUTHORITY OUT OF MEMORY?
    #
    # PERM_LOAD_CAPABILITY (bit 4) and PERM_STORE_CAPABILITY (bit 5) exist in the
    # Perms table, CAndPerm faithfully clears them, CGetPerm faithfully reports
    # them cleared -- and before this test nothing on either layer ever read them.
    # OCL.C and OCS.C were authorised by the plain DATA permissions, because they
    # call veda_check_access with need_load / need_store and nothing else.
    #
    # In an address-less machine where ALL authority is capabilities, that is the
    # difference between "you may read these bytes" and "you may pick up the
    # authority stored in them". This test is the difference, run rather than
    # argued:
    #
    #   an owner stores a capability naming a SECRET object into a container,
    #   then delegates the container with bit 4 cleared -- data only.
    #   The delegate runs OCL.C and, if nothing checks bit 4, receives a LIVE,
    #   TAGGED capability naming an object it was never given.
    #
    #   x21  CONTROL: the owner's own un-attenuated capability CAN load it back,
    #        tag 1 and Object_ID 771 -- without this the test would pass just as
    #        happily if OCS.C had silently stored nothing
    #   x22  THE ESCAPE IS REFUSED: cause 0x14, and the destination stays untagged
    #   x23  the store side too: STORE without STORE_CAPABILITY -> cause 0x15
    #   x20  traps -- exactly 2
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x25, 0
    li   x6, 0

    # container object 770: Load|Store|LoadCap|StoreCap = 0x003C
    li   x1, 770
    li   x2, 0x800114000040003C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # the SECRET object 771 -- the authority that must not travel
    li   x1, 771
    li   x2, 0x800115000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 770
    .insn i 0x0b, 0x5, x0, x1, 0          # bind c0 -> container, full perms
    li   x1, 771
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1 -> secret

    # the owner puts the secret capability inside the container
    .insn r 0x0b, 0x4, 0x01, x1, x0, x6   # ocs.c  mem=c0, src=c1, off=0

    # ---- CONTROL: the owner can read it back, so the store really happened
    .insn r 0x0b, 0x4, 0x00, x4, x0, x6   # ocl.c c4 <- [c0 + 0]
    .insn r 0x5b, 0x0, 0x03, x12, x4, x0  # cgettag c4
    li   t1, 1
    bne  x12, t1, fail
    .insn r 0x5b, 0x0, 0x07, x13, x4, x0  # cgetobjectid c4
    li   t1, 771
    bne  x13, t1, fail
    li   t1, 0
    bne  x20, t1, fail                    # and it took no trap
    li   x21, 0x600D

    # ---- the delegation: data only. Clear bit 4, keep bit 2.
    li   x4, 0xFFEF
    .insn r 0x5b, 0x1, 0x17, x2, x0, x4   # candperm c2 = c0 & ~LOAD_CAPABILITY
    .insn r 0x5b, 0x0, 0x02, x10, x2, x0  # cgetperm c2
    andi x11, x10, 0x10
    bnez x11, fail                        # bit 4 is really clear
    andi x11, x10, 0x04
    beqz x11, fail                        # and plain LOAD really survives

    # ---- THE ESCAPE ATTEMPT
    .insn r 0x0b, 0x4, 0x00, x3, x2, x6   # ocl.c c3 <- [c2 + 0]
    .insn r 0x5b, 0x0, 0x03, x12, x3, x0  # cgettag c3
    bnez x12, fail                        # a tagged capability was lifted = ESCAPE
    # cap_idx in mtval is the rs1 capability -- the one being DEREFERENCED (c2),
    # not the destination c3. Every family shares that field position; the first
    # draft of this line said 0x74 and the bisection caught it.
    li   t1, 0x54                          # (c2 << 5) | 0x14 PERMIT_LOAD_CAPABILITY
    bne  x25, t1, fail
    li   t1, 1
    bne  x20, t1, fail
    li   x22, 0x600D

    # ---- and the store side: STORE without STORE_CAPABILITY
    li   x4, 0xFFDF
    .insn r 0x5b, 0x1, 0x17, x5, x0, x4   # candperm c5 = c0 & ~STORE_CAPABILITY
    .insn r 0x5b, 0x0, 0x02, x10, x5, x0  # cgetperm c5
    andi x11, x10, 0x20
    bnez x11, fail                        # bit 5 is clear
    andi x11, x10, 0x08
    beqz x11, fail                        # and plain STORE survives
    .insn r 0x0b, 0x4, 0x01, x1, x5, x6   # ocs.c mem=c5, src=c1 -- must be refused
    li   t1, 0xB5                          # (c5 << 5) | 0x15 PERMIT_STORE_CAPABILITY
    bne  x25, t1, fail
    li   t1, 2
    bne  x20, t1, fail
    li   x23, 0x600D

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
