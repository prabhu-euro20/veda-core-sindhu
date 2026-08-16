.section .text
.global _start
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x0, 0x00, x3, x1, x0
    sd   x3, 0(x31)
    .insn r 0x5b, 0x0, 0x01, x3, x1, x0
    sd   x3, 8(x31)
    .insn r 0x5b, 0x0, 0x02, x3, x1, x0
    sd   x3, 16(x31)
    .insn r 0x5b, 0x0, 0x03, x3, x1, x0
    sd   x3, 24(x31)
    .insn r 0x5b, 0x0, 0x04, x3, x1, x0
    sd   x3, 32(x31)
    .insn r 0x5b, 0x0, 0x05, x3, x1, x0
    sd   x3, 40(x31)
    .insn r 0x5b, 0x0, 0x06, x3, x1, x0
    sd   x3, 48(x31)
    .insn r 0x5b, 0x0, 0x07, x3, x1, x0
    sd   x3, 56(x31)

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
