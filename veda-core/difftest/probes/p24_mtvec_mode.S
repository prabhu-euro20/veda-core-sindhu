.section .text
.global _start
# R80 -- mtvec MODE. The RTL used mtvec[1:0] as ADDRESS bits; Sail legalised them.
#
# RISC-V Privileged section 3.1.7, verbatim: "the CSR contains only bits XLEN-1
# through 2 of the address BASE. When used as an address, the lower two bits are
# filled with zeroes to obtain an XLEN-bit address that is always aligned on a
# 4-byte boundary." The RTL filled them with MODE instead -- $alt_pc is $mtvec
# raw, with no MODE decode and no +4*cause arm anywhere in the file.
#
# THIS PROBE EXISTS BECAUSE THE DIFFERENTIAL SUITE SHOULD HAVE CAUGHT IT AND DID
# NOT: 25 probes, and not one wrote a non-zero MODE to mtvec. The whole corpus
# installs its vector with `la` + `csrw`, which is always 4-byte aligned, so the
# divergent bits were never exercised. A suite that only ever writes legal values
# cannot find a WARL defect.
#
#   w0  Reserved MODE 0b10 via csrwi        -- must read back 0
#   w2  Reserved MODE 0b11 via csrrs over a real base -- must read back the base
#   w4  Vectored MODE 0b01, a LEGAL mode    -- must read back the base, MODE stripped
#   w6  CONTROL, ANTI-VACUITY: an already-aligned write must survive UNCHANGED.
#       Without this row a core that returned zero for every mtvec read would
#       pass every row above.
#   w8  THE ONE THAT MATTERED: install the handler with MODE=0b01 and take a real
#       trap. 0xC0DE only if the handler actually executed AND returned. This is
#       the row where the two layers used to part company permanently -- Sail
#       entered at base, this core fetched ONE BYTE INTO the handler from its
#       byte-granular instruction array and never came back.
_start:
    li   x31, 0x80070000

    csrwi mtvec, 2                  # MODE = 0b10, Reserved
    csrr x2, mtvec
    sd   x2, 0(x31)                 # w0

    li   x3, 0x80001000
    csrw mtvec, x3
    li   x4, 3
    csrrs x0, mtvec, x4             # MODE |= 0b11, Reserved
    csrr x5, mtvec
    sd   x5, 8(x31)                 # w2

    li   x6, 0x80002000
    ori  x6, x6, 1                  # MODE = 0b01, Vectored -- a legal mode
    csrw mtvec, x6
    csrr x7, mtvec
    sd   x7, 16(x31)                # w4

    li   x8, 0x80003000             # already aligned, MODE = 0b00
    csrw mtvec, x8
    csrr x9, mtvec
    sd   x9, 24(x31)                # w6  CONTROL

    la   x30, trap_handler
    ori  x30, x30, 1                # install the REAL handler with MODE = 0b01
    csrw mtvec, x30
    li   x20, 0
    ecall
    sd   x20, 32(x31)               # w8  0xC0DE iff the handler ran and returned

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    li   x20, 0xC0DE
    csrr x22, mepc
    addi x22, x22, 4
    csrw mepc, x22
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
