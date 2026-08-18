.section .text
.global _start
# R50 INCREMENT 1 -- OCLEAR, cross-layer.
#
# R50 measured that the capability register file crosses a compartment boundary
# intact, and the conventional answer is that a trusted switcher clears what it
# is not passing. THIS MACHINE COULD NOT DO THAT: no instruction reliably zeroed
# a capability register's VALUE. Every soft-fail in the derivation family clears
# the tag and carries the source's fields verbatim, and veda.bind.notrap on a
# live, openly-bindable slot SUCCEEDS and installs a full capability instead of
# clearing. The architecture had assigned a duty and shipped no tool.
#
# This probe can live in the differential harness -- unlike R48's -- because
# OCLEAR needs no compartment crossing, and a crossing is what R51 makes
# unreachable here (no region is resident with test_fixtures false, so every
# OCInvoke REGION_FAULTs).
#
#   w0  cgetbase of the target BEFORE the clear -- nonzero and equal on both.
#       Without it, w2's zero proves nothing: a register that was always zero
#       reads zero after any implementation, including one that does nothing.
#   w1  cgettag  after the clear -- 0
#   w2  cgetbase after the clear -- 0. THE VALUE, NOT JUST THE TAG: the query
#       family is deliberately un-gated, so a tag-only clear would still answer
#       here with the raw physical Base. RTL-14 already paid for that once.
#   w3  cgettype after the clear -- 0xFFFF, NOT 0. isSealedCap tests
#       otype != UNSEALED_OTYPE and Rebind tests it on its DESTINATION with no
#       tag conjunct, so an all-zeros clear leaves every cleared register
#       permanently un-Rebindable while its tag reads 0 either way. R24 again.
#   w4  cgettag of an UNMASKED register -- 1. OVER-REFUSAL CONTROL: a layer that
#       wiped the whole file on this opcode gets w1-w3 right and fails here.
#   w5  a value loaded through that unmasked register -- 0xBEEF. The deeper form
#       of the same control: still tagged AND still dereferenceable.
#   w6  cgettag after re-binding the cleared register -- 1, proving w3's choice
#       is load-bearing and not cosmetic.
#   w7  trap count -- 0. OCLEAR is unprivileged and raises nothing. (The User-
#       mode proof is in sail_tests/vc_r50_oclear.S; this harness runs at
#       Machine.)
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    li   x1, 140
    li   x2, 0x8003000000200004            # Base 0x80030000, Len 0x20, Perms Load
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # Object 141 is the one actually DEREFERENCED, so it needs real backing
    # memory and Load|Store -- the first draft gave it Perms 0x0004 (Load only)
    # and then stored through it, which trapped. Caught by reading w5 and w7
    # rather than the AGREE verdict; the two layers had agreed on a failure.
    la   x3, arena
    slli x3, x3, 32
    li   x4, (32 << 16) | 0x000C           # Len 0x20, Perms Load|Store
    or   x2, x3, x4
    li   x1, 141
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 140
    .insn i 0x0b, 0x5, x5, x1, 0           # veda.bind c5, 140
    li   x1, 141
    .insn i 0x0b, 0x5, x6, x1, 0           # veda.bind c6, 141

    .insn r 0x5b, 0x0, 0x00, x20, x5, x0   # cgetbase x20, c5 -- BEFORE
    sd   x20, 0(x31)                       # w0

    li   x7, 0
    li   x8, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x8, x6, x7    # ocs.d c6, x7, x8

    li   x9, 0x0020                        # bit 5 only
    .insn r 0x5b, 0x1, 0x18, x0, x0, x9    # oclear x9

    .insn r 0x5b, 0x0, 0x03, x21, x5, x0   # cgettag  x21, c5
    .insn r 0x5b, 0x0, 0x00, x22, x5, x0   # cgetbase x22, c5
    .insn r 0x5b, 0x0, 0x04, x23, x5, x0   # cgettype x23, c5
    sd   x21, 8(x31)                       # w1
    sd   x22, 16(x31)                      # w2
    sd   x23, 24(x31)                      # w3

    .insn r 0x5b, 0x0, 0x03, x24, x6, x0   # cgettag x24, c6  -- unmasked
    sd   x24, 32(x31)                      # w4
    li   x7, 0
    li   x25, 0
    .insn r 0x0b, 0x3, 0x00, x25, x6, x7   # ocl.d x25, x7, c6
    sd   x25, 40(x31)                      # w5

    li   x1, 140
    .insn i 0x0b, 0x5, x5, x1, 2           # veda.rebind c5, 140
    .insn r 0x5b, 0x0, 0x03, x26, x5, x0   # cgettag x26, c5
    sd   x26, 48(x31)                      # w6
    sd   x29, 56(x31)                      # w7

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
.balign 32
arena:
    .space 32
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
