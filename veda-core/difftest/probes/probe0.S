.section .text
.global _start
_start:
    li   x1, 0x80070000
    li   x2, 0xAAAA
    sd   x2, 0(x1)
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0      # veda.bind c1, 1
    .insn r 0x5b, 0x0, 0x00, x3, x1, x0   # cgetbase x3, c1
    li   x1, 0x80070000
    sd   x3, 8(x1)
    .insn r 0x5b, 0x0, 0x01, x4, x1, x0   # cgetlen  x4, c1
    sd   x4, 16(x1)
    # HTIF halt
    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
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
