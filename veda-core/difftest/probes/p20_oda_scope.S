.section .text
.global _start
# R47 -- THE ODA IS A CAPABILITY WHOSE WINDOW NEITHER LAYER READ.
#
# veda_oda_authorized() is three terms wide on both layers:
#   Sail : veda_ocl_insts.sail  veda_oda_tag & not(isSealedCap(veda_oda))
#                               & permBit(veda_oda.Perms, PERM_ACCESS_SYSTEM_REGISTERS)
#   RTL  : veda_core.tlv        $veda_oda_tag && !$veda_oda_sealed && $veda_oda_perms[7]
# Tag, otype, one permission bit. Base, Length, Offset and Object_ID -- 196 of
# the ODA's 256 bits -- were consulted by NONE of the seven instructions this
# predicate authorizes. Delegated authority over the Object Descriptor Table was
# therefore a BEARER TOKEN over all of memory.
#
# The escape was already in the RTL suite, PASSING: rtl/sim/veda_smoke_m11.S
# installed an ODA whose window is [0x80011000, 0x80011040), dropped to User,
# and from User minted object 41 at Base 0x80012000 -- four kilobytes outside
# it -- then Bound it and read back its Base. That file's own comment calls this
# "the real proof" the ODA path works. It is. It is also the escape, pinned as
# the contract, which is why this probe exists on the differential harness where
# both layers must say the same thing.
#
# THE RULE: on the DELEGATED path only, the memory a descriptor names must lie
# inside the ODA's window. Machine takes the other half of the
# `Machine | oda_authorized()` OR, needs no ODA, and is deliberately untouched.
#
#   w0  mcause of a User-mode Populate OUTSIDE the ODA's window -- 0x02 on both
#   w1  tag of a Bind against that Object_ID -- 0: the refusal PREVENTED the
#       mint, it did not merely trap after writing. Counting a refusal is not
#       checking it.
#   w2  tag of a Bind against an object minted INSIDE the window -- 1. THE
#       OVER-REFUSAL CONTROL, and it is the load-bearing word here: a layer that
#       simply refused every delegated Populate would produce the right answer
#       for w0 and w1 and the wrong one here.
#   w3  its Base -- 0x80011000, proving the mint really happened rather than
#       leaving a stale register
#   w4  mcause of a User-mode Destroy of a descriptor OUTSIDE the window -- 0x02.
#       Destroy is scoped too: it bumps the generation of any slot it touches,
#       so an unscoped delegate could burn the temporal-safety counter of every
#       object in the machine.
#   w5  trap count -- 2, and it pins that CONTROL 1 and the in-window Destroy
#       below added none
#   w6  tag of a Bind against the in-window object after a User-mode Destroy of
#       it -- 0. The second over-refusal control, on Destroy rather than
#       Populate: in-window Destroy must still WORK.
#   w7  Base of a Machine-minted object outside the window -- 0x80012000. Machine
#       holds the ODA at that moment and is still not scoped by it. Without this
#       word a fix that scoped BOTH halves of the OR would pass everything above
#       while breaking the machine.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0                            # trap count
    li   x28, 0                            # last mcause

    # ─── Machine: mint the authority object and scope it to 64 bytes ──────
    # object 40: Base 0x80011000, Length 0x40, Perms 0x0080 (PERM_ASR)
    li   x1, 40
    li   x2, 0x8001100000400080
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # veda.odt.populate 40
    li   x1, 40
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, 40
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0    # ospecialrw c2, c1   -- ODA := c1

    # w7's subject: Machine mints OUTSIDE the window it now holds. Done before
    # the drop, while the ODA is already installed, so the word means "Machine
    # is not scoped" rather than "no ODA was present".
    li   x1, 43
    li   x2, 0x8001200000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # veda.odt.populate 43 at 0x80012000
    li   x1, 43
    .insn i 0x0b, 0x5, x7, x1, 1           # veda.bind.notrap c7, 43
    .insn r 0x5b, 0x0, 0x00, x20, x7, x0   # cgetbase x20, c7

    # ─── drop to User the architected way (R36): MPP = 0b00, then mret ────
    li   x1, 0x1800
    csrc mstatus, x1
    la   x3, umode
    csrw mepc, x3
    mret

umode:
    # ═══ the escape veda_smoke_m11.S used to demonstrate ══════════════════
    li   x1, 41
    li   x2, 0x8001200000400300            # Base 0x80012000 -- outside [0x80011000,0x80011040)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # veda.odt.populate 41 -- must refuse
    sd   x28, 0(x31)                       # w0 -- mcause

    li   x1, 41
    .insn i 0x0b, 0x5, x4, x1, 1           # veda.bind.notrap c4, 41
    .insn r 0x5b, 0x0, 0x03, x21, x4, x0   # cgettag x21, c4
    sd   x21, 8(x31)                       # w1 -- 0: nothing was minted

    # ═══ CONTROL 1 -- in-window Populate must still SUCCEED ═══════════════
    li   x1, 42
    li   x2, 0x8001100000200300            # Base 0x80011000, Length 0x20 -- inside
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # veda.odt.populate 42
    li   x1, 42
    .insn i 0x0b, 0x5, x6, x1, 0           # veda.bind c6, 42
    .insn r 0x5b, 0x0, 0x03, x22, x6, x0   # cgettag  x22, c6
    .insn r 0x5b, 0x0, 0x00, x23, x6, x0   # cgetbase x23, c6
    sd   x22, 16(x31)                      # w2 -- 1
    sd   x23, 24(x31)                      # w3 -- 0x80011000

    # ═══ Destroy is scoped too ════════════════════════════════════════════
    li   x1, 43
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    # veda.odt.destroy 43 -- outside, must refuse
    sd   x28, 32(x31)                      # w4 -- mcause

    # ═══ CONTROL 2 -- in-window Destroy must still WORK ═══════════════════
    li   x1, 42
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    # veda.odt.destroy 42
    sd   x29, 40(x31)                      # w5 -- trap count, 2
    li   x1, 42
    .insn i 0x0b, 0x5, x8, x1, 1           # veda.bind.notrap c8, 42
    .insn r 0x5b, 0x0, 0x03, x24, x8, x0   # cgettag x24, c8
    sd   x24, 48(x31)                      # w6 -- 0: really gone

    sd   x20, 56(x31)                      # w7 -- 0x80012000, Machine unscoped

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mcause
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
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
