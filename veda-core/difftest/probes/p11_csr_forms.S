.section .text
.global _start
# R33c -- ALL SIX Zicsr FORMS.
#
# Four were missing (CSRRC, CSRRWI, CSRRSI, CSRRCI). They are a class-B debt --
# ALLOCATED in the claimed ISA, absent here -- so a decode catch-all would have
# turned them into illegal-instruction, a different wrong answer.
#
# THEY ALSO SILENTLY DEFEATED R32, WHICH HAD ALREADY SHIPPED. $veda_csr_undef is
# gated on $is_csr_access, and that was the OR of CSRRW and CSRRS only, so a
# csrrci to a nonexistent CSR was DOUBLY silent -- the instruction did not decode
# AND the address check did not fire. w10 is that case.
#
# The access-type table is the part that is easy to get wrong:
# csr_access_type() makes a SET or CLEAR whose source is zero a pure READ that
# must NOT write. `csrr rd, csr` is exactly that, and this core's trap handlers
# use it constantly. w6 pins it.
#
#   w0  csrrw  then read back        -- the register write form
#   w2  csrrc  clears the bits it is given
#   w4  csrrwi writes a zero-extended 5-bit immediate
#   w6  csrrsi with imm=0 must NOT write -- pure read
#   w8  csrrci clears via an immediate
#   w10 csrrci to an UNDEFINED CSR must trap -- the R32 hole these four punched
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x2, 0x0F0
    csrrw x0, 0x340, x2                    # mscratch = 0x0F0
    csrr  x3, 0x340
    sd    x3, 0(x31)                        # 0x0F0

    li    x2, 0x030
    csrrc x0, 0x340, x2                    # clear bits 0x030 -> 0x0C0
    csrr  x3, 0x340
    sd    x3, 8(x31)                        # 0x0C0

    csrrwi x0, 0x340, 21                   # write the 5-bit immediate 21
    csrr   x3, 0x340
    sd     x3, 16(x31)                      # 21

    csrrsi x4, 0x340, 0                    # imm=0 -> pure READ, must not write
    csrr   x3, 0x340
    sd     x3, 24(x31)                      # still 21

    csrrci x0, 0x340, 5                    # clear bits 5 -> 21 & ~5 = 16
    csrr   x3, 0x340
    sd     x3, 32(x31)                      # 16

    csrrci x0, 0x7c9, 1                    # UNDEFINED CSR -- must trap
    sd     x29, 40(x31)                     # 1 on both once R32 sees this form

    # THE PURE-READ RULE, MADE OBSERVABLE. A mutant forcing $csr_write_en true
    # SURVIVED the phase above, and rightly: csrrsi with imm=0 writes
    # `old | 0`, which is `old`, so the register is unchanged either way and the
    # probe could not tell a pure read from a read-modify-write. Same vacuity
    # shape the census keeps finding.
    #
    # 0x7C6 is READ-ONLY -- Sail's is_CSR_accessible clause for it carries
    # `access_type == CSRRead`, and R32 mirrors that with
    # ($csr_write_en && $csr_is_readonly). So `csrr x3, 0x7c6`, which IS
    # csrrs with rs1=x0, is the discriminator: under the correct rule it is a
    # pure read and must NOT trap; with the rule broken it becomes a write to a
    # read-only CSR and traps. The value is incidental -- the trap count is the
    # measurement.
    csrr   x3, 0x7c6                       # read-only CSR via the csrrs form
    sd     x29, 48(x31)                     # still 1 -- no new trap
    csrrsi x4, 0x7c6, 0                    # and the immediate form, same rule
    sd     x29, 56(x31)                     # still 1

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
