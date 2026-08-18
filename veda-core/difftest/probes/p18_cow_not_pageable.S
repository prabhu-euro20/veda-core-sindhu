.section .text
.global _start
# R38(b) -- A COPY-ON-WRITE OBJECT IS NOT PAGEABLE, ON BOTH LAYERS.
#
# R38 made the copy-on-write split right belong to whoever held PERM_STORE at the
# moment the object became copy-on-write. set.cow deliberately does not bump the
# generation, so that entitlement lives in exactly one place: the live capability
# registers that predate it.
#
# veda.odt.page.out exists to destroy exactly those. It bumps the generation --
# which is how outstanding capabilities are invalidated, and is necessary because
# every capability caches its own Base and page-in supplies a new one -- while
# carrying `cow` across untouched. One round trip left an object NOBODY could
# split: every pre-cow capability stale, the entry still copy-on-write, and the
# only way back in a Bind that masks store off.
#
# AND CLEARING `cow` IS NOT THE RECOVERY IT LOOKS LIKE. On a genuinely shared
# object it lets EVERY sharer write THE SAME object -- precisely the isolation
# copy-on-write was providing. A recovery that silently merges two writers is
# worse than the lockout it repairs. So the refusal is placed at the instruction
# that destroys the evidence, not attempted afterwards from state that is gone.
#
# THE COST IS STATED, NOT HIDDEN: a shared object cannot be evicted until the
# sharing resolves. It cannot be weaponised -- page.out and set.cow both require
# Machine or ODA authority, so unprivileged code cannot pin memory this way.
#
#   w0  the entitled pre-cow holder splits -- mtval 0x0C
#   w1  page.out on the copy-on-write object is REFUSED -- mcause 0x02
#   w2  and BECAUSE it was refused the entitlement survives: 0x0C again. This
#       word is the whole increment.
#   w3  CONTROL: a NON-cow object still pages out and back in with no trap, so
#       the refusal is a policy about copy-on-write and not a broken page.out
#   w4  traps -- exactly 3
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x28, 0                            # last mcause
    li   x27, 0                            # last mtval

    li   x1, 760
    li   x2, 0x800118000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 760, Load|Store
    li   x1, 760
    .insn i 0x0b, 0x5, x0, x1, 0           # bind c0 BEFORE cow -- keeps store
    li   x1, 760
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2    # veda.odt.set.cow 760 <- 1

    li   x3, 0
    li   x4, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3    # ocs.d c0 -- COW fault
    sd   x27, 0(x31)                       # w0 -- 0x0C

    li   x1, 760
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- must be REFUSED
    sd   x28, 8(x31)                       # w1 -- mcause 0x02

    .insn r 0x0b, 0x3, 0x01, x4, x0, x3    # ocs.d c0 again -- the right survived
    sd   x27, 16(x31)                      # w2 -- 0x0C

    li   x1, 761
    li   x2, 0x800119000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 761 -- NOT cow
    li   x1, 761
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0    # page.out -- must SUCCEED
    li   x2, 0x80011900
    li   x1, 761
    .insn r 0x0b, 0x0, 0x05, x5, x1, x2    # page.in  -- must SUCCEED
    sd   x29, 24(x31)                      # w3 -- traps STILL 3, nothing new
    sd   x29, 32(x31)                      # w4 -- 3

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mcause
    csrr x27, mtval
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
    mret
.section .data
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 8, 8, 0
.global end_signature
end_signature:
