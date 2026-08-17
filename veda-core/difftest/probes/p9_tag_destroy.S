.section .text
.global _start
# R33 -- A CAPABILITY-DESTRUCTION PRIMITIVE REACHABLE FROM AN UNALLOCATED
# ENCODING, and the reason the base-ISA catch-all must NOT be shipped alone.
#
# veda_core.tlv:5638 opens `if (act4_mode && $is_store && !purecap_violation)`.
# Inside it the DATA write is an if/else-if chain on is_sb/is_sh/is_sw/is_sd with
# NO else -- so an unallocated store writes nothing, which is why it looks
# harmless. But the TAG INVALIDATION at :5668 is a SEPARATE if at the same
# nesting level, gated only by the umbrella $is_store, and :1282 defines that as
# `$is_store = $op_is_store` -- OPCODE ONLY, no funct3 test.
#
# So a store with funct3 in {100,101,110,111} -- encodings RV64I never allocated
# -- CLEARS THE CAPABILITY TAG at rs1+imm and writes no data. A silent
# capability kill from an instruction that does not exist.
#
# THIS IS ALSO WHY A CATCH-ALL ALONE WOULD MAKE THINGS WORSE. None of the
# side-effect paths are gated on $veda_trap_taken, so adding only the catch-all
# yields a machine that reports mcause 0x02 with mtval holding the word -- which
# a handler correctly reads as "the instruction did not execute" -- while the
# tag clear still happened. It would look closed, the suite would pass, and the
# primitive would survive behind an illegal-instruction report. The decode
# tightening has to land FIRST.
#
#   w0  tag after storing a capability  -- 1 on both, the setup worked
#   w2  tag after the unallocated store -- Sail 1 (refused), RTL 0 (destroyed)
#   w4  trap count                      -- Sail 1, RTL 0
#   w6  CONTROL: a LEGAL sd to the same granule also clears the tag, on both.
#       Without this the probe could not distinguish "unallocated stores are
#       special" from "stores clear tags", which is the whole point.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x1, 70
    li   x2, 0x800109000040103C            # Base=0x80010900 Len=0x40 Perms=Load|Store|LoadCap|StoreCap
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 70
    li   x1, 70
    .insn i 0x0b, 0x5, x1, x1, 0           # bind c1, 70
    li   x3, 0
    .insn r 0x0b, 0x4, 0x01, x1, x1, x3    # ocs.c c1, 0, c1 -- a real tagged capability in memory
    .insn r 0x0b, 0x4, 0x00, x2, x1, x3    # ocl.c c2, c1, 0 -- read it back
    .insn r 0x5b, 0x0, 0x03, x4, x2, x0    # cgettag c2
    sd   x4, 0(x31)                         # must be 1 on both -- the setup worked

    li   x5, 0x80010900
    .word 0x0002C023                        # S-type, funct3=100, rs1=x5, rs2=x0, imm=0
                                            # UNALLOCATED in RV64I -- there are four
                                            # store widths and this is not one of them
    .insn r 0x0b, 0x4, 0x00, x6, x1, x3    # ocl.c c6, c1, 0 -- read the capability again
    .insn r 0x5b, 0x0, 0x03, x7, x6, x0    # cgettag c6
    sd   x7,  8(x31)                        # Sail 1 (store refused), RTL 0 (tag destroyed)
    sd   x29, 16(x31)                       # Sail 1 trap, RTL 0

    # CONTROL: a LEGAL store to the same granule clears the tag on both layers.
    .insn r 0x0b, 0x4, 0x01, x1, x1, x3    # ocs.c -- put the capability back
    sd   x0, 0(x5)                          # legal sd -- clears the tag by design
    .insn r 0x0b, 0x4, 0x00, x8, x1, x3
    .insn r 0x5b, 0x0, 0x03, x9, x8, x0
    sd   x9, 24(x31)                        # 0 on both -- tag clearing itself is correct

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
