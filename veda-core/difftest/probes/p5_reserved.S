.section .text
.global _start
# R30 -- ENCODINGS THE SPECIFICATION NAMES AS ILLEGAL, AND THE HARDWARE IGNORES.
#
# Three observations, each an encoding that Sail refuses and the RTL may not:
#   w0/w1  veda.bind mode 0b11 = VEDA_BIND_RESERVED. Not an "undefined" encoding:
#          veda_bind_insts.sail:276 maps it to Illegal_Instruction() by name, and
#          the RTL decodes only modes 00/01/10 (veda_core.tlv:1380/1393/1400)
#          with no arm for 11 at all.
#   w2/w3  custom-0 funct3=000 funct7=0001010. That space defines exactly three
#          funct7 values -- 0000011 Populate, 0000100 Populate-Fast, 0000101
#          page-in -- so 125 of 128 are unallocated.
#   w4/w5  custom-2 funct3=111. The whole funct3 is unallocated on that opcode.
#
# w6/w7 is the control: the SAME instruction family at a LEGAL encoding must not
# trap, so a layer that simply traps on everything cannot pass this probe.
#
# x29 counts traps and is stored after each step, so the probe reports WHICH
# encoding was refused rather than only how many were.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 1 -- mode 00, legal, sets up state

    .insn i 0x0b, 0x5, x2, x1, 3          # BIND MODE 3 -- specified Illegal_Instruction
    sd   x29, 0(x31)                       # expect 1
    sd   x27, 40(x31)                      # A-3/R44: and its CAUSE -- 0x02 on both

    li   x6, 8
    .insn r 0x0b, 0x0, 0x0a, x7, x1, x6   # custom-0 f3=000 f7=0001010 -- unallocated
    sd   x29, 8(x31)                       # expect 2
    sd   x27, 48(x31)                      # its cause -- 0x02

    .insn r 0x5b, 0x7, 0x00, x8, x1, x0   # custom-2 f3=111 -- unallocated funct3
    sd   x29, 16(x31)                      # expect 3
    sd   x27, 56(x31)                      # its cause -- 0x02

    .insn r 0x5b, 0x0, 0x03, x9, x1, x0   # cgettag c1 -- LEGAL, must NOT trap
    sd   x29, 24(x31)                      # expect 3 still
    sd   x9,  32(x31)                      # and it must have produced a real answer

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    # A-3/R44: THIS HANDLER USED TO READ ONLY mepc. It counted traps and never
    # looked at WHY, so three probes that exist to prove "unallocated encodings are
    # refused" could not tell an Illegal_Instruction from a REGION_FAULT. Mode 0b11
    # really did report a different cause on the two layers, for years, and this
    # probe reported AGREE throughout. Counting a refusal is not checking it.
    csrr x27, mcause
    csrr x28, mepc
    addi x28, x28, 4
    csrw mepc, x28
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
    .fill 16, 8, 0
.global end_signature
end_signature:
