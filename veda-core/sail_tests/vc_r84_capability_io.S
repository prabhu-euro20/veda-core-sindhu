.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R84 -- A CAPABILITY REACHES A DEVICE, AND THIS IS THE FIRST TEST IN THIS
#        PROJECT THAT RUNS ITS WHOLE STEADY STATE UNDER PURECAP AND HALTS
#        WITHOUT EVER TURNING IT OFF.
#
# It began life as poc_r84_purecap_has_no_io.S and COULD NOT PASS. Every row
# below succeeded even then -- traced instruction by instruction -- and the test
# still spun forever, because RVMODEL_HALT_PASS_PURECAP signals through OCS.D and
# Veda's OCL/OCS family called read_ram/write_ram DIRECTLY. MMIO routing lives one
# layer up, at sys/mem.sail:461, and covers the CLINT, the signature region and
# HTIF. So a capability reached RAM and nothing else, while purecap forbids the
# ordinary accesses that CAN reach a device: the machine had no way to say it had
# finished.
#
# VEDA_OCL/VEDA_OCS now route through mem_read_priv_meta /
# mem_write_value_priv_meta -- the upstream checked path, already tag-carrying and
# already MMIO-aware. The file is kept verbatim apart from this header, so the
# ONLY thing that changed between "cannot pass" and "passes" is the memory path.
#
#   ROW A  purecap really is on            -- 0x7C5 reads 1
#   ROW B  an ordinary ld is refused HERE  -- 1 trap, cause 0x07
#   ROW C  and it loaded nothing           -- 0
#   ROW D  a CAPABILITY access still works -- OCL.D reads back what OCS.D wrote
#          Without D this file proves only that the machine is broken.
#   and it halts through OCS.D, with purecap STILL ON.
.equ SECRET, 251
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0

    la   x6, secret
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x000C
    or   x2, x6, x7
    li   x1, SECRET
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, SECRET
    .insn i 0x0b, 0x5, x9, x1, 0

    li   x11, 1
    csrw 0x7C5, x11                          # PURECAP ON -- and it stays on
    csrr x20, 0x7C5
    li   x17, 1
    bne  x20, x17, fail                      # ROW A

    li   x8, 0
    li   x10, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x10, x9, x8     # ROW D: capability STORE under purecap
    li   x23, 0
    .insn r 0x0b, 0x3, 0x00, x23, x9, x8     # ROW D: capability LOAD  under purecap
    li   x17, 0xC0FFEE
    bne  x23, x17, fail
    bnez x27, fail                           # and neither took a trap

    la   x12, secret
    li   x22, 0
    ld   x22, 0(x12)                         # ROW B/C: an ORDINARY load -- refused
    li   x17, 1
    bne  x27, x17, fail
    li   x17, 0x07
    bne  x26, x17, fail
    bnez x22, fail

    RVMODEL_HALT_PASS_PURECAP
fail:
    RVMODEL_HALT_FAIL_PURECAP
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    andi x26, x26, 0x1f
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.balign 64
secret:
    .space 64
