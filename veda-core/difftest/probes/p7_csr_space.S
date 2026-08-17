.section .text
.global _start
# R32 -- THE CSR ADDRESS SPACE IS FAIL-OPEN TOO, and the instruction-encoding
# catch-all cannot reach it.
#
# Sail is fail-closed here by exactly the construction it uses for encodings:
# postlude/csr_end.sail:11 is a last wildcard `is_CSR_accessible(_) = false`,
# structurally identical to the wildcard ILLEGAL clause in insts_end.sail.
# veda_regs.sail declares accessibility for 0x7C0..0x7C8 only, so 0x7C9 falls to
# the wildcard -> CSR_Illegal -> Illegal_Instruction.
#
# The RTL has no address-validity term anywhere: $csr_rdata's default arm is
# 64'b0, and neither $veda_illegal_instr nor $veda_trap_taken carries an
# unknown-CSR term. So an undefined CSR reads as ZERO, silently -- which is
# worse than a no-op, because zero is a value software can act on.
#
# And the encoding catch-all cannot help: $veda_op_claimed ORs the four custom
# opcodes, while a CSR access is opcode 1110011. Two separate fail-open
# surfaces, two separate fixes.
#
# w4/w5 is the control: a DEFINED Veda CSR must still read normally, so a layer
# that refused the whole 0x7Cx range could not pass this.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x2, 0x1234
    csrrw x1, 0x7c9, x2                   # 0x7C9: undefined in Sail's accessibility map
    sd   x29, 0(x31)                       # Sail 1 trap, RTL 0
    sd   x1,  8(x31)                       # RTL reads 0 -- a value, not a fault

    csrr x3, 0x7c1                         # CONTROL: veda_pcc_length, defined
    sd   x3,  16(x31)                      # must be 0xFFFFFFFFFF on both
    sd   x29, 24(x31)                      # and must not have added a trap

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
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
    .fill 8, 8, 0
.global end_signature
end_signature:
