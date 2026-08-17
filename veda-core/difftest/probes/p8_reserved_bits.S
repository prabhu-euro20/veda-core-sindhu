.section .text
.global _start
# R30(b) -- RESERVED-ZERO BITS INSIDE ALLOCATED ENCODINGS.
#
# The R30 catch-all is opcode/funct3/funct7/selector-granular. Sail pins bits
# BELOW that granularity, and a 1 in any of them means no encdec clause matches,
# so the wildcard ILLEGAL catches it. This layer never looks at them, so the
# allocated instruction just executes.
#
# Five classes, from the encdec clauses. Each is measured separately, and the
# trap counter is stored after EACH so the probe reports WHICH class was refused
# rather than only how many were:
#   w0  bit 19 set above a 4-bit vcap rs1   (every OCL/OCS/query/cap clause)
#   w2  bit 11 set above a 4-bit vcap rd    (OCL.C, OCA, CSETBOUNDS, CSEAL, ...)
#   w4  bit 24 set above a 4-bit vcap rs2   (CSEAL, CUNSEAL, OCINVOKE, OCJALR)
#   w6  rd field nonzero on OCRETURN        (consumes no destination register)
#   w8  rs2 field nonzero on a CapQuery     (pinned to 00000)
#
# w10 is the control: the SAME instructions at their LEGAL encodings must not
# trap, so a layer that refused the whole family could not pass this.
#
# The vcap fields are FOUR bits with a hardwired zero above them, which is why
# these bits exist at all: a capability register file has 16 entries, not 32, so
# the fifth bit of each register field is reserved rather than absent.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1, 1 -- legal, sets up a real capability

    # bit 19 above the vcap rs1 of cgettag: 0x5b | f3=000 | f7=0000011
    # rs1 field is bits[19:15]; vcap is [18:15] and bit 19 must be 0.
    .insn r 0x5b, 0x0, 0x03, x3, x17, x0  # rs1=x17 -> bit19=1, vcap=1
    sd   x29, 0(x31)

    # bit 11 above the vcap rd of csetbounds: 0x5b | f3=001 | f7=0001000
    .insn r 0x5b, 0x1, 0x08, x17, x1, x1  # rd=x17 -> bit11=1, vcap=1
    sd   x29, 8(x31)

    # bit 24 above the vcap rs2 of cseal: 0x5b | f3=001 | f7=0010000
    .insn r 0x5b, 0x1, 0x10, x2, x1, x17  # rs2=x17 -> bit24=1, vcap=1
    sd   x29, 16(x31)

    # rd field nonzero on ocreturn, which consumes no destination.
    #
    # THE TRAP COUNT IS NOT ENOUGH HERE, and a mutant proved it. c1 is not a
    # sentry, so even if this decoded it would fail OCReturn's own checks and
    # trap anyway -- identical count, different reason. Forcing
    # $veda_resv_rd_zero true therefore SURVIVED the count-only version of this
    # probe. mcause separates them: an unallocated encoding is 0x02
    # (illegal instruction), an OCReturn that decodes and then fails its checks
    # is 0x18 (a Veda trap). Same shape as the census lesson -- a phase can pass
    # for the wrong reason on one axis while looking right on another.
    .insn r 0x5b, 0x1, 0x16, x5, x1, x0
    sd   x29, 24(x31)
    sd   x27, 56(x31)                      # mcause of that trap: 0x02, not 0x18

    # rs2 field nonzero on a CapQuery, which pins it to 00000
    .insn r 0x5b, 0x0, 0x03, x3, x1, x9
    sd   x29, 32(x31)

    # CONTROL: the same query at its legal encoding
    .insn r 0x5b, 0x0, 0x03, x4, x1, x0   # cgettag c1 -- all reserved bits zero
    sd   x4,  40(x31)
    sd   x29, 48(x31)

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
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
    .fill 8, 8, 0
.global end_signature
end_signature:
