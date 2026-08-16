.section .text
.global _start
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x2, 0
    .insn r 0x5b, 0x1, 0x08, x2, x1, x2
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x2, x2
    sd   x28, 0(x31)
    li   x2, 64
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2
    sd   x28, 8(x31)
    li   x2, 8
    .insn r 0x0b, 0x4, 0x01, x1, x1, x2
    sd   x28, 16(x31)
    li   x2, 0
    .insn r 0x0b, 0x3, 0x01, x3, x11, x2
    sd   x28, 24(x31)
    li   x1, 999
    .insn i 0x0b, 0x5, x8, x1, 0
    sd   x28, 32(x31)
    sd   x29, 40(x31)

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mtval
    csrr x27, mepc
    addi x27, x27, 4
    csrw mepc, x27
    mret
.section .tohost, "aw", @progbits
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
