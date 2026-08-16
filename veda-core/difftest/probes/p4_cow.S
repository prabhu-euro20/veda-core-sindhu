.section .text
.global _start
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x0, 0x02, x3, x1, x0
    sd   x3, 0(x31)
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0
    .insn r 0x5b, 0x0, 0x02, x3, x2, x0
    sd   x3, 8(x31)
    li   x1, 1
    .insn i 0x0b, 0x5, x6, x1, 2
    .insn r 0x5b, 0x0, 0x02, x3, x6, x0
    sd   x3, 16(x31)
    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2
    sd   x28, 24(x31)
    sd   x29, 32(x31)
    li   x1, 1
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4

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
