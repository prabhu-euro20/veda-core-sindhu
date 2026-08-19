.include "veda_selfcheck_macros.S"
# NOT RUN BY THE SUITE, DELIBERATELY. The runner globs vc_*.S; this is poc_*.
# A PASS here means the ESCALATION WORKS.
.section .text
.global _start
# R81 -- THE ODA'S WINDOW BOUNDS WHAT ITS HOLDER MAY CREATE, AND NOT WHAT IT MAY
#        BIND. Residue made visible by R79.
#
# R47 adopted the rule "on the DELEGATED path only, the memory a descriptor names
# must lie inside the ODA's own window", and applied it to the seven ODT
# management instructions. veda.bind is NOT one of the seven and reads no ODA
# field at all -- `grep -c oda veda_bind_insts.sail` returns 0, and the RTL's
# $veda_bind_domain_ok has no ODA-window term either.
#
# Before R79 this was invisible because arm 2 of veda_bind_domain_ok granted
# ambient root to EVERYBODY at User. R79 removed everyone except Machine and ODA
# holders -- which is what makes the remaining grant legible, and is exactly the
# question this register requires after concentrating an authority: who else now
# stands where it was concentrated?
#
#   ROW A  ATTACK   : User + ODA binds an object at `out`, OUTSIDE its window,
#                     and dereferences it. If x21 = 1 and x23 = 0xC0FFEE the
#                     window is not bounding the bind path.
#   ROW B  CONTROL  : the same principal binds the object INSIDE its window.
#                     Must be 1, or ROW A proves only that binding is broken.
#   ROW C  CONTROL  : boot itself is unaffected -- it bound OUTSIDE at Machine.
#   ROW D  LEDGER   : no traps anywhere. bind mode 1 soft-fails, so a refusal
#                     would show as tag 0 rather than as a trap.
#
# Every register by NUMBER.
.equ AUTH,    240
.equ INSIDE,  241
.equ OUTSIDE, 242
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0

    # ─── the authority, scoped to `win` and to `win` ALONE ───────────────
    la   x6, win
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x0080            # PERM_ACCESS_SYSTEM_REGISTERS
    or   x2, x6, x7
    li   x1, AUTH
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # ─── one object INSIDE the window, one OUTSIDE it, both boot-owned ───
    la   x6, win
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x000C            # PERM_LOAD | PERM_STORE
    or   x2, x6, x7
    li   x1, INSIDE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    la   x6, out
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x000C
    or   x2, x6, x7
    li   x1, OUTSIDE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # ─── boot writes the secret into OUTSIDE, then proves it can read it ──
    li   x1, OUTSIDE
    .insn i 0x0b, 0x5, x9, x1, 0
    .insn r 0x5b, 0x0, 0x03, x24, x9, x0    # ROW C: boot bound it at Machine
    li   x8, 0
    li   x10, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x10, x9, x8    # ocs.d c9 <- 0xC0FFEE

    # ─── install the ODA, then drop to User ──────────────────────────────
    li   x1, AUTH
    .insn i 0x0b, 0x5, x11, x1, 0
    .insn r 0x5b, 0x1, 0x13, x12, x11, x0   # ospecialrw -- ODA := c11
    bnez x27, fail                          # setup was clean

    li   x13, 0x1800
    csrc mstatus, x13
    la   x14, umode
    csrw mepc, x14
    mret

.balign 4
umode:
    # ═══ ROW A -- THE ATTACK. Bind by NAME an object the ODA does not cover.
    li   x1, OUTSIDE
    .insn i 0x0b, 0x5, x14, x1, 1           # bind.notrap into c14 -- soft-fails if refused
    .insn r 0x5b, 0x0, 0x03, x21, x14, x0   # cgettag c14
    li   x8, 0
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x23, x14, x8   # ocl.d through c14 -- does it READ?

    # ═══ ROW B -- CONTROL. The same principal, an object INSIDE the window.
    li   x1, INSIDE
    .insn i 0x0b, 0x5, x13, x1, 1           # bind.notrap into c13
    .insn r 0x5b, 0x0, 0x03, x22, x13, x0   # cgettag c13 -- must be 1

verdict:
    li   x17, 1
    bne  x24, x17, fail                     # ROW C: boot bound OUTSIDE at Machine
    bne  x22, x17, fail                     # ROW B: in-window bind works
    bne  x21, x17, fail                     # ROW A: OUT-of-window bind SUCCEEDED
    li   x17, 0xC0FFEE
    bne  x23, x17, fail                     # ROW A: and it READ the secret
    bnez x27, fail                          # ROW D: and it took no trap
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x18, mepc
    addi x18, x18, 4
    csrw mepc, x18
    mret
.section .data
.balign 64
win:
    .space 64
out:
    .space 64
