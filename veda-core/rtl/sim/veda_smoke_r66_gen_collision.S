.section .text
.global _start
// R66 -- the retirement lands one Populate too late. The RTL half.
//
// `$veda_odt_retired` is computed from the OLD generation, so a slot at
// {valid, 0xFFFFFE} takes a Populate that saturates it and leaves retired still
// false; the NEXT Populate then passes, cannot bump, and writes a second
// incarnation at the SAME generation while the first one's capabilities are live.
//
// Measured on Sail before the fix: the old capability read 0xABCD out of arena1,
// the frame the descriptor had abandoned, while arena2 stayed zero.
//
// Entry 106 is the seeded {valid, 0xFFFFFE} fixture -- the RTL's own comment
// calls its distance from the ceiling "the load-bearing detail".
// Every register by number.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0

    // --- incarnation 1, over the seeded 0xFFFFFE slot, at arena1
    la   x6, arena1
    slli x6, x6, 32
    li   x7, 0x0020000C                     // Len 0x20, Load|Store
    or   x2, x6, x7
    li   x1, 106
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     // Populate //1
    mv   x18, x27                            // traps so far

    li   x1, 106
    .insn i 0x0b, 0x5, x3, x1, 0            // bind c3 -- incarnation 1
    .insn r 0x5b, 0x0, 0x03, x19, x3, x0    // cgettag
    li   x8, 0
    li   x9, 0xABCD
    .insn r 0x0b, 0x3, 0x01, x9, x3, x8     // ocs.d c3 -- write a marker into arena1
    mv   x20, x27

    // --- incarnation 2, SAME slot, DIFFERENT frame
    la   x6, arena2
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, 106
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     // Populate //2 -- gate reads the OLD retired
    mv   x21, x27                            // 0 new traps means it was ACCEPTED

    // --- THE MEASUREMENT: is incarnation 1's capability still live?
    li   x8, 0
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x3, x8    // ocl.d through c3
    mv   x22, x27
    // and does it reach arena1 -- the frame the descriptor no longer names?
    la   x11, arena1
    ld   x12, 0(x11)
    la   x13, arena2
    ld   x14, 0(x13)
check:
    bnez x18, done                          // CONTROL 1: populate //1 accepted
    li   x16, 1
    bne  x19, x16, done                     // CONTROL 2: the bind minted
    bnez x20, done                          // CONTROL 3: the write worked
    li   x16, 1
    bne  x21, x16, done                     // THE FINDING: populate //2 must TRAP
    li   x16, 1
    bne  x22, x16, done                     // the old capability still works
    li   x16, 0xABCD
    bne  x10, x16, done
    bne  x12, x16, done
    bnez x14, done
    li   x23, 0x600D
    j    done
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
done:
1:
    j 1b
.section .data
.balign 64
arena1:
    .space 64
arena2:
    .space 64
