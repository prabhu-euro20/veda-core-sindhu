.section .text
.global _start
// R24 -- THE CAPABILITY REGISTER FILE HAS AN ARCHITECTURAL RESET STATE.
//
// THIS LAYER WAS ALREADY RIGHT, and that is exactly why the test belongs here.
// The RTL resets every non-fixture capability register to otype 0xFFFF, which
// its own comment calls "the default means UNSEALED". Sail left the whole file
// at struct-default zero, and zero is a LEGITIMATE seal type -- isSealedCap is
// `otype != 0xFFFF`, and CSeal really can mint otype 0, since the otype it
// produces is just the sealing authority's Offset.
//
// One enforcement decision reads sealedness with NO tag conjunct:
// $veda_rebind_sealed = ($veda_rdcap_otype != 16'hFFFF), no tag term, feeding
// $veda_rebind_ok. So `rebind` into a never-written register SUCCEEDED here and
// silently soft-failed on Sail. Same rule, both layers; only the reset value
// differed, and it changed what the instruction did.
//
// So this test does not verify a fix -- it pins a value that was correct and
// unguarded. Nothing in this corpus was watching it: the reset otype could have
// been changed to anything and all 87 tests would have stayed green.
//
// c9 is the subject: outside the fixture range on BOTH layers (this layer seeds
// c11-c14, Sail seeds c10-c14), so it is genuinely untouched rather than merely
// untouched here.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // ---- P0: the reset value itself, read before anything writes it ----
    .insn r 0x5b, 0x0, 0x04, x10, x9, x0   # cgettype c9  -- must be 0xFFFF
    .insn r 0x5b, 0x0, 0x03, x11, x9, x0   # cgettag  c9  -- must be 0

    li   x1, 70
    li   x2, 0x800109000040100C            // Base=0x80010900 Len=0x40 Perms=Load|Store|NMC
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 70

    // ---- P1: rebind into the NEVER-WRITTEN register must SUCCEED ----
    // The single-term discriminator. Every other gate Rebind applies -- domain,
    // residency, valid, owner -- is satisfied by construction, so the only
    // thing that can refuse is the destination's own sealedness, which is
    // decided entirely by the reset otype.
    li   x1, 70
    .insn i 0x0b, 0x5, x9, x1, 2           # rebind c9, 70
    .insn r 0x5b, 0x0, 0x03, x12, x9, x0   # cgettag  c9  -- must be 1
    .insn r 0x5b, 0x0, 0x00, x13, x9, x0   # cgetbase c9  -- must be 0x80010900
    .insn r 0x5b, 0x0, 0x01, x14, x9, x0   # cgetlen  c9  -- must be 0x40

    // ---- P2: control -- rebind into a GENUINELY sealed register soft-fails
    // Without this, deleting the sealed term outright would still pass P1 and
    // the test would measure nothing but "rebind works". The authority needs a
    // non-zero Length: CSeal demands cs2.Offset < cs2.Length, because an
    // authority may only mint otypes inside its own range.
    li   x1, 71
    li   x2, 0x8001098000400300            // Base=0x80010980 Len=0x40 Perms=Seal|Unseal
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 71
    li   x1, 71
    .insn i 0x0b, 0x5, x7, x1, 0           # bind c7, 71  -- the seal authority
    li   x1, 70
    .insn i 0x0b, 0x5, x8, x1, 0           # bind c8, 70
    .insn r 0x5b, 0x1, 0x10, x8, x8, x7    # cseal c8, c8, c7
    .insn r 0x5b, 0x0, 0x03, x15, x8, x0   # cgettag c8 -- still 1 after sealing
    li   x1, 70
    .insn i 0x0b, 0x5, x8, x1, 2           # rebind c8, 70 -- must SOFT-FAIL
    .insn r 0x5b, 0x0, 0x03, x16, x8, x0   # cgettag c8 -- must now be 0

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
