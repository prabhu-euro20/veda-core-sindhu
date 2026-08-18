.section .text
.global _start
_start:
    // R59 -- a re-minted object inherited the previous occupant's owner.
    //
    // Sail resets owner_hart = VEDA_OWNER_UNOWNED on Populate, Populate-Fast AND
    // Destroy. This file's ONLY dynamic write to the owner byte was the owner
    // CLAIM -- it never reset -- so a slot's owner survived Destroy and
    // re-Populate and a fresh object was born owned by whoever last held it.
    //
    // Benign at MHARTID = 0 and PERMANENT above it: no instruction in the ISA
    // writes that byte except the claim, so hart A could never reclaim a slot
    // hart B once bound, even after destroying and re-minting it. R41's class
    // applied to the third carried field.
    //
    // Observable on one hart only because Milestone 12 seeded three slots at
    // owner_hart = 0x63 ("hart 99"), a value owner_ok refuses. Entries 60 and
    // 105 are re-minted here; 109 is the untouched control. Nothing software can
    // do on one hart produces that value, which is why this cannot be tested
    // fixture-free -- and the two layers seed DIFFERENT slots, so the Sail half
    // lives in sail_tests/vc_r59_owner_hart_reset.S on objects 5 and 615.
    la   x30, trap_handler
    csrw mtvec, x30
    li   x29, 0
    li   x28, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0

    // CONTROL 1: the fixture is what this test thinks it is.
    li   x1, 60
    .insn i 0x0b, 0x5, x3, x1, 0           // veda.bind c3, 60 -- PLAIN
    li   x4, 1
    bne  x29, x4, done
    andi x4, x28, 0x1f
    li   x5, 0x06
    bne  x4, x5, done                      // OWNER violation, as seeded
    li   x20, 0x600D

    // THE FINDING: re-mint the slot and the owner must go with it.
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C                    // Len 0x20, Perms Load|Store
    or   x2, x6, x7
    li   x1, 60
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // veda.odt.populate 60
    li   x4, 1
    bne  x29, x4, done                     // the populate must not trap
    li   x1, 60
    .insn i 0x0b, 0x5, x8, x1, 0           // veda.bind c8, 60 -- PLAIN
    li   x4, 1
    bne  x29, x4, done                     // MUST NOT have trapped again
    .insn r 0x5b, 0x0, 0x03, x4, x8, x0    // cgettag
    li   x5, 1
    bne  x4, x5, done
    li   x21, 0x600D

    // CONTROL 2: usable, not merely tagged.
    li   x9, 0
    li   x10, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x10, x8, x9   // ocs.d c8
    li   x11, 0
    .insn r 0x0b, 0x3, 0x00, x11, x8, x9   // ocl.d  c8
    mv   x22, x11

    // CONTROL 3: an UNTOUCHED 0x63 slot must still refuse. Without this a core
    // that simply stopped checking owner_ok passes everything above.
    li   x1, 109
    .insn i 0x0b, 0x5, x12, x1, 0          // veda.bind c12, 109
    li   x4, 2
    bne  x29, x4, done
    andi x4, x28, 0x1f
    li   x5, 0x06
    bne  x4, x5, done
    li   x23, 0x600D

    // THE SAME FOR DESTROY.
    li   x1, 105
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0    // veda.odt.destroy 105
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, 105
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // and re-mint it
    li   x1, 105
    .insn i 0x0b, 0x5, x13, x1, 0          // veda.bind c13, 105 -- PLAIN
    li   x4, 2
    bne  x29, x4, done                     // no third trap
    .insn r 0x5b, 0x0, 0x03, x4, x13, x0
    li   x5, 1
    bne  x4, x5, done
    li   x24, 0x600D
done:
1:  j 1b

.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mtval
    csrr x27, mepc
    addi x27, x27, 4
    csrw mepc, x27
    mret

.section .data
.balign 32
arena:
    .space 32
