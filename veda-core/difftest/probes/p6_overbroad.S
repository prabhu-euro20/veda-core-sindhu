.section .text
.global _start
# R30(b) -- OVER-BROAD DECODERS. Not fail-open-SILENT: fail-open-ACTIVE.
#
# These are worse than an unallocated encoding that no-ops. Here the RTL decodes
# encodings the architecture never allocated and executes them AS A DEFINED
# INSTRUCTION, performing the real state change. Sail refuses every one of them,
# because its encdec mappings pin the fields and anything unmatched falls to the
# wildcard ILLEGAL clause (postlude/insts_end.sail).
#
#   w0  veda.bind with imm[11:2] != 0. veda_core.tlv:1351 tests opcode+funct3
#       only and reads the mode from $instr[21:20]; Sail's encdec pins
#       0b0000000000 @ mode, so 1023 of 1024 upper-immediate patterns are
#       refused there. THIS IS THE REACHABLE ONE -- Bind MINTS CAPABILITIES.
#   w2  custom-1 atomic with an unallocated op-select. veda_core.tlv:1738 tests
#       opcode+funct3 only.
#   w4  OSpecialRW with an SCR selector outside {ODA, TSC, SSC}. Sail's
#       encdec_veda_scr maps exactly three values. The RTL gates the ODA write
#       on !is_tsc && !is_ssc, so 29 undefined selectors WRITE THE ODA -- the
#       one Special Capability Register that authorises privileged object
#       operations. Machine-mode only, so not an unprivileged escalation; it is
#       an unallocated encoding performing an authority-register swap.
#   w6  was "veda.droppriv with funct3 != 000", where the decoder omitted the
#       funct3 test entirely so all 8 values reached $priv = 0. R30 narrowed the
#       decode; R36 then retired the instruction outright and unclaimed Custom-3,
#       so this encoding is now illegal for a STRONGER reason -- the whole major
#       opcode is unallocated on both layers, which is what the model always
#       said, having never defined a Custom-3 clause. Same observable, same
#       verdict; kept because an encoding that was once executed is worth
#       continuing to prove is refused.
#
# w8 is the control: a LEGAL bind must still work on both layers, so a layer
# that simply refused this whole family could not pass.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 4          # bind, mode 00 but imm[2]=1 -- Sail refuses
    .insn r 0x5b, 0x0, 0x03, x3, x2, x0   # cgettag c2
    sd   x3,  0(x31)                       # RTL: 1 (a capability was minted). Sail: 0
    sd   x29, 8(x31)                       # RTL: 0 traps. Sail: 1

    .insn r 0x2b, 0x3, 0x7c, x4, x1, x1   # custom-1 atomic, unallocated op-select
    sd   x29, 16(x31)

    .insn r 0x5b, 0x1, 0x13, x5, x1, x6   # ospecialrw, rs2 field = SCR selector 6 (undefined)
    sd   x29, 24(x31)

    .insn r 0x5b, 0x0, 0x03, x7, x1, x0   # CONTROL: cgettag c1 -- legal, must not trap
    sd   x7,  32(x31)
    sd   x29, 40(x31)

    .insn r 0x7b, 0x2, 0x00, x0, x0, x0   # droppriv with funct3=010 -- LAST, it drops privilege
    sd   x29, 48(x31)

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
