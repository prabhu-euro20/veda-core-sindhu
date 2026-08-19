.section .text
.global _start
# R79 -- the ambient root had THREE occupants and only one of them is boot.
#
# veda_pcc_object has exactly four writers per layer and only the two crossings
# install a NAME, so the ambient sentinel -- which R75/R76 increment 1 turned
# into the root of all authority -- is reachable as boot (Machine, intended), as
# a trap handler (Machine, R77, still open), and as USER CODE ENTERED BY A
# PRIVILEGE DROP. The third crossed nothing, holds nothing, and is not trusted
# code: it is the ordinary shape of an OS process. It held the root.
#
# This probe pins the rule ACROSS LAYERS, which is what the Sail-only negative
# test cannot do. If the RTL fails to mirror the Machine-or-ODA conjunct, w2
# diverges immediately.
#
#   w0  CONTROL, at MACHINE: boot binds its own object   -- 1 on both (boot intact)
#   w2  THE RULE, at USER with no ODA and no crossing:
#          bind.notrap a boot-owned object                -- 0 on both (REFUSED)
#   w4  ANTI-VACUITY, same User principal, same instant:
#          bind.notrap an ANY-DECLARED object             -- 1 on both
#          Without w4 a core that refused every User bind passes w2 for the
#          wrong reason.
#   w6  trap count -- 0 on both. bind.notrap soft-fails; the refusal must be
#       quiet, not a trap, or w2 would be measuring the wrong mechanism.
.equ SECRET, 220
.equ PUBLIC, 221
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x27, 0

    la   x6, secret
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, SECRET
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # boot populates -> owner_domain BOOT

    la   x6, public
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, PUBLIC
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, PUBLIC
    li   x2, 0xFFFFF                        # VEDA_DOMAIN_ANY -- declared public
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    li   x1, SECRET                         # w0 CONTROL, at Machine
    .insn i 0x0b, 0x5, x9, x1, 1
    .insn r 0x5b, 0x0, 0x03, x20, x9, x0
    sd   x20, 0(x31)

    li   x12, 0x1800                        # drop to User, MPP = 0b00
    csrc mstatus, x12
    la   x13, umode
    csrw mepc, x13
    mret
.balign 4
umode:
    li   x1, SECRET                         # w2 THE RULE
    .insn i 0x0b, 0x5, x10, x1, 1
    .insn r 0x5b, 0x0, 0x03, x21, x10, x0
    sd   x21, 8(x31)

    li   x1, PUBLIC                         # w4 ANTI-VACUITY
    .insn i 0x0b, 0x5, x14, x1, 1
    .insn r 0x5b, 0x0, 0x03, x22, x14, x0
    sd   x22, 16(x31)

    sd   x27, 24(x31)                       # w6 trap count

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.balign 64
secret:
    .space 64
public:
    .space 64
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 8, 8, 0
.global end_signature
end_signature:
