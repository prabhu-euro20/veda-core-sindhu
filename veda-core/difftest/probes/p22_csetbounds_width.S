.section .text
.global _start
# R53 -- CSetBounds IS COMPUTED AT THE WRONG WIDTH IN THE RTL.
#
#   Sail  veda_cap_insts.sail: Base = cap.Base + zero_extend(cap.Offset)   (56 bits)
#                              Length = new_length[39 .. 0]                (40 bits)
#   RTL   veda_core.tlv:       $veda_csetbounds_new_base[31:0]   = base + offset
#                              $veda_csetbounds_new_length[15:0] = $rs2_data[15:0]
#
# The operands are 56 and 40 bits wide on both layers ($veda_rs1cap_base[55:0],
# $veda_rs1cap_offset[39:0]) and the results are consumed into $base[55:0] and
# $length[39:0]. So the RTL narrows a derived capability to the PRE-INCREMENT-3
# widths -- 32-bit Base, 16-bit Length -- which the ODT entry stopped having when
# the capability format was widened. It looks like a site that widening missed,
# and it sits in the same mux the R50 crossing clear will have to edit.
#
# REACHABILITY, and the two halves differ:
#   Length: reachable NOW. Any object whose Length exceeds 0xFFFF, narrowed to a
#           request above 0xFFFF, diverges. This probe drives exactly that.
#   Base:   needs Base+Offset >= 2^32, which this testbench's memory map cannot
#           reach. Recorded as unmeasured rather than claimed.
#
#   w0  Length of a CSetBounds-derived capability, requested 0x10000
#       Sail: 0x10000.  RTL: 0x0000 -- the request truncated to 16 bits is zero.
#   w1  its Base -- equal on both here, since Base stays below 4 GiB
#   w2  CONTROL: the same derivation with a request of 0x0040, which fits 16 bits.
#       Both layers must agree, or the probe is measuring a broken CSetBounds
#       rather than a width divergence.
#   w3  CONTROL: the parent object's own Length, read before any derivation --
#       0xFFFFFFFFFF on both. Proves the wide Length survives Bind, so the loss
#       below is CSetBounds's and not the ODT's or Bind's.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    # An UNBOUNDED object: Length 0xFFFFFFFFFF via the wide populate path.
    li   t1, 0xFFFFFFFFFF
    slli t1, t1, 16
    ori  t1, t1, 0x000C                    # Perms Load|Store
    csrw 0x7c4, t1                         # veda_attr = Length[55:16] | Perms[15:0]
    la   t2, arena
    li   x1, 70
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # veda.odt.populate.fast 70

    li   x1, 70
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, 70
    .insn r 0x5b, 0x0, 0x01, x20, x1, x0   # cgetlen x20, c1
    sd   x20, 24(x31)                      # w3 -- the parent's own Length

    # THE DIVERGENCE: request a Length that does not fit 16 bits.
    li   x2, 0x10000
    .insn r 0x5b, 0x1, 0x08, x3, x1, x2    # csetbounds c3, c1, x2
    .insn r 0x5b, 0x0, 0x01, x21, x3, x0   # cgetlen  x21, c3
    .insn r 0x5b, 0x0, 0x00, x22, x3, x0   # cgetbase x22, c3
    sd   x21, 0(x31)                       # w0 -- Sail 0x10000, RTL 0x0000
    sd   x22, 8(x31)                       # w1 -- Base, equal below 4 GiB

    # CONTROL: a request that fits 16 bits must agree on both layers.
    li   x2, 0x0040
    .insn r 0x5b, 0x1, 0x08, x4, x1, x2    # csetbounds c4, c1, x2
    .insn r 0x5b, 0x0, 0x01, x23, x4, x0   # cgetlen x23, c4
    sd   x23, 16(x31)                      # w2 -- 0x40 on both

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
    mret
.section .data
.align 3
arena:
    .space 128
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
