.section .text
.global _start
# R81 -- an authority's scope bounds what it authorises. The ODA's window bounded
# what its holder could CREATE (R47, seven ODT instructions) and bounded nothing
# about what it could BIND -- veda.bind is the eighth consumer and read no ODA
# field at all. Measured before it was designed, and the numbers below are the
# measurement inverted into a cross-layer contract.
#
#   w0  CONTROL : boot binds an OUT-of-window object at MACHINE   -> 1 both
#   w2  THE RULE: the ODA holder at User binds the same object     -> 0 both
#   w4  and reads nothing through it                                -> 0 both
#   w6  CONTROL : the same holder binds an IN-window object         -> 1 both
#                 Without w6, a core that refused every delegated bind passes w2
#                 for the wrong reason.
#   w8  trap ledger. bind mode 1 soft-fails, so the refusal is quiet; the one
#       trap is the ocl.d through the now-untagged register.
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
    li   x31, 0x80070000
    sd   x24, 0(x31)                        # w0  ROW C boot bound OUTSIDE at Machine
    sd   x21, 8(x31)                        # w2  ROW A tag of the OUT-of-window bind
    sd   x23, 16(x31)                       # w4  ROW A value read through it
    sd   x22, 24(x31)                       # w6  ROW B tag of the IN-window bind
    sd   x27, 32(x31)                       # w8  ROW D trap count
    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
fail:
    j    verdict
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x18, mepc
    addi x18, x18, 4
    csrw mepc, x18
    mret
.section .data
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.balign 64
win:
    .space 64
out:
    .space 64
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 8, 8, 0
.global end_signature
end_signature:
