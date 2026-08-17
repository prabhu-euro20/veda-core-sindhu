.section .text
.global _start
# R37 -- THE SPECIAL CAPABILITY REGISTERS NEVER GOT R24's FIX.
#
# R24 gave the capability register FILE a defined architectural reset, because
# Sail's struct-default leaves otype at 0x0000 and isSealedCap is
# `otype != UNSEALED_OTYPE` with UNSEALED_OTYPE = 0xFFFF -- so an untouched
# register read as SEALED WITH TYPE ZERO, a type CSeal can really mint.
#
# The three Special Capability Registers -- ODA, TSC, SSC -- were not in that
# fix and still are not reset at all on the Sail side:
#     register veda_oda : capability        <- no initialiser
# while the RTL resets each of their otypes to 16'hFFFF explicitly
# (veda_core.tlv:4057, :4098, and the SSC analogue).
#
# IT IS NOT COSMETIC ON THIS REGISTER IN PARTICULAR. veda_oda_authorized() reads
#     veda_oda_tag & not(isSealedCap(veda_oda)) & permBit(Perms, bit 7)
# so the ODA's sealedness is an input to the gate on EVERY ODT-mutating
# instruction. Today the tag is false on both layers so the gate is false either
# way -- but that is fail-closed by accident of a different field, not by this
# one being right. The same latent shape R24 closed for the CRF.
#
# OSpecialRW SWAPS, so the reset value is directly observable: it reads the old
# SCR into rd and installs rs1. Reading each of the three out and querying its
# otype is a clean cross-layer measurement, unlike the privilege model, because
# OSpecialRW exists on both layers and needs only Machine, which both have at
# reset.
#
#   w0  otype of the reset ODA   -- Sail 0x0000, RTL 0xFFFF
#   w2  otype of the reset TSC
#   w4  otype of the reset SSC
#   w6  tag of the reset ODA     -- 0 on both; the field that makes it harmless today
#   w8  CONTROL: otype of an untouched CRF register, which R24 already fixed --
#       0xFFFF on both, so the probe is measuring the SCRs specifically and not
#       some general disagreement about what an unwritten capability looks like.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    .insn r 0x5b, 0x1, 0x13, x2, x0, x0   # ospecialrw c2, ODA, c0  -- c2 = the reset ODA
    .insn r 0x5b, 0x0, 0x04, x3, x2, x0   # cgettype c2
    sd   x3, 0(x31)

    .insn r 0x5b, 0x1, 0x13, x4, x0, x1   # ospecialrw c4, TSC, c0
    .insn r 0x5b, 0x0, 0x04, x3, x4, x0   # cgettype c4
    sd   x3, 8(x31)

    .insn r 0x5b, 0x1, 0x13, x5, x0, x2   # ospecialrw c5, SSC, c0
    .insn r 0x5b, 0x0, 0x04, x3, x5, x0   # cgettype c5
    sd   x3, 16(x31)

    .insn r 0x5b, 0x0, 0x03, x3, x2, x0   # cgettag c2 -- the reset ODA's tag
    sd   x3, 24(x31)

    .insn r 0x5b, 0x0, 0x04, x3, x9, x0   # CONTROL: cgettype c9, untouched, R24-fixed
    sd   x3, 32(x31)
    sd   x29, 40(x31)                      # traps: 0 on both

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
