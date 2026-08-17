.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # R24 -- THE CAPABILITY REGISTER FILE HAS AN ARCHITECTURAL RESET STATE.
    #
    # Every other Veda register is reset explicitly in ext_reset(). The CRF was
    # the only one that never was, so all sixteen registers came up at Sail's
    # struct-default zero -- INCLUDING otype. And zero is a legitimate seal
    # type: isSealedCap is `otype != UNSEALED_OTYPE` with UNSEALED_OTYPE =
    # 0xFFFF, so an untouched register read as SEALED WITH TYPE ZERO, a type
    # CSeal really can mint, since the otype it produces is just the sealing
    # authority's Offset.
    #
    # NOT COSMETIC, and P1 is why. One enforcement decision reads sealedness
    # with NO tag conjunct: Rebind soft-fails on isSealedCap(destination) alone,
    # where the destination is whatever the target register happens to hold. So
    # `rebind` into a never-written register silently refused on this layer and
    # SUCCEEDED on the RTL, whose reset otype is 0xFFFF. Same rule on both
    # layers -- the RTL's $veda_rebind_sealed is likewise `otype != 16'hFFFF`
    # with no tag term. Only the reset value differed, and it changed what the
    # instruction DID.
    #
    # The RTL is the correct one: 0xFFFF is the architecturally reserved "no
    # type", CSeal refuses it as a requested otype, and no sealing can produce
    # it. 0x0000 is an accident of zero-initialisation that aliases a real type.
    #
    # zero_capability in veda_types.sail already spelled this state out exactly
    # -- every field zero, otype = UNSEALED_OTYPE -- and had no callers at all.
    # The constant was written and never applied.
    #
    # c9 is the subject: outside the fixture range on BOTH layers (Sail seeds
    # c10-c14, the RTL seeds c11-c14), so it is genuinely untouched rather than
    # merely untouched here.
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    # ---- P0: the reset value itself, read before anything writes it ----
    .insn r 0x5b, 0x0, 0x04, x10, x9, x0   # cgettype c9  -- must be 0xFFFF
    .insn r 0x5b, 0x0, 0x03, x11, x9, x0   # cgettag  c9  -- must be 0

    li   x1, 70
    li   x2, 0x800109000040100C            # Base=0x80010900 Len=0x40 Perms=Load|Store|NMC
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 70

    # ---- P1: rebind into the NEVER-WRITTEN register must SUCCEED ----
    # This is the single-term discriminator. Every other gate Rebind applies --
    # domain, residency, e.valid, owner_ok -- is satisfied by construction, so
    # the only thing that can refuse here is the destination's own sealedness,
    # which is decided entirely by the reset otype.
    li   x1, 70
    .insn i 0x0b, 0x5, x9, x1, 2           # rebind c9, 70
    .insn r 0x5b, 0x0, 0x03, x12, x9, x0   # cgettag  c9  -- must be 1
    .insn r 0x5b, 0x0, 0x00, x13, x9, x0   # cgetbase c9  -- must be 0x80010900
    .insn r 0x5b, 0x0, 0x01, x14, x9, x0   # cgetlen  c9  -- must be 0x40

    # ---- P2: control -- rebind into a GENUINELY sealed register must soft-fail
    # Without this, deleting the isSealedCap branch outright would still pass
    # P1, and the test would be measuring nothing but "rebind works".
    # The authority needs a non-zero Length: CSeal demands cs2.Offset <
    # cs2.Length, because the otype it mints IS the authority's Offset and an
    # authority may only mint otypes inside its own range.
    li   x1, 71
    li   x2, 0x8001098000400300            # Base=0x80010980 Len=0x40 Perms=Seal|Unseal
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 71
    li   x1, 71
    .insn i 0x0b, 0x5, x7, x1, 0           # bind c7, 71   -- the seal authority
    li   x1, 70
    .insn i 0x0b, 0x5, x8, x1, 0           # bind c8, 70
    .insn r 0x5b, 0x1, 0x10, x8, x8, x7    # cseal c8, c8, c7  -- c8 is now sealed
    .insn r 0x5b, 0x0, 0x03, x15, x8, x0   # cgettag c8 -- still 1 after sealing
    li   x1, 70
    .insn i 0x0b, 0x5, x8, x1, 2           # rebind c8, 70 -- must SOFT-FAIL
    .insn r 0x5b, 0x0, 0x03, x16, x8, x0   # cgettag c8 -- must now be 0

    li   x21, 0xDEAD
    li   x22, 0xDEAD

    li   x3, 0xFFFF                        # P0: reset otype is UNSEALED
    bne  x10, x3, done
    bne  x11, x0, done                     # P0: reset tag is clear
    li   x3, 1                             # P1: rebind into a fresh register works
    bne  x12, x3, done
    li   x3, 0x80010900
    bne  x13, x3, done
    li   x3, 0x40
    bne  x14, x3, done
    li   x3, 1                             # P2: sealing leaves the tag set
    bne  x15, x3, done
    bne  x16, x0, done                     # P2: rebind onto sealed clears it
    bne  x20, x0, done                     # nothing here may trap

    li   x21, 0x600D
    li   x22, 0x900D

done:
    li   x3, 0x600D
    bne  x21, x3, real_fail
    li   x3, 0x900D
    bne  x22, x3, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL

trap_handler:
    addi x20, x20, 1
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
