.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R66 -- the retirement lands one Populate too late, and two incarnations end up
# sharing one generation.
#
# `retired` is computed from the OLD generation, so a slot at {valid, 0xFFFFFE}
# takes a Populate that saturates it to 0xFFFFFF and leaves retired STILL FALSE.
# The next Populate then passes the gate, cannot bump (saturating no-op), and
# writes a SECOND incarnation at the same generation -- while the first
# incarnation's capabilities are live and carry that generation. The
# dereference's only temporal arm is `entry.generation != cap.generation`, and
# `retired` is read by no dereference arm on either layer.
#
# MEASURED BEFORE THE FIX, by instruction trace, over the seeded 0xFFFFFE slot:
#   [12] populate #1 at arena1  ->  accepted
#   [15] bind, [20] ocs.d 0xABCD ->  written into arena1
#   [29] populate #2 at arena2  ->  ACCEPTED, no trap
#   [33] ocl.d through the OLD capability -> 0xABCD, read out of arena1
# arena2 stayed zero. After the fix the same binary shows
#   [29] populate -> [30] trap_handler+0.
#
# THE SOURCE ALREADY KNEW. Page-out's own comment says of this state: "That
# state is genuinely reachable, not theoretical ... So `retired` does not
# intercept it", and page-out FAILS CLOSED on it. The defence was written for
# the instruction that OBSERVES the state, not for the one that CREATES it.
#
# Object 55 is the seeded {valid, 0xFFFFFE} fixture. Software alone cannot reach
# that generation -- 16.7M populates -- which is why the fixture exists, the same
# standing R59's owner_hart fixture has.
#
# Every register by number: x27 traps, x26 mtval, x17 handler temp.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0

    # --- incarnation 1, over the seeded 0xFFFFFE slot, at arena1
    la   x6, arena1
    slli x6, x6, 32
    li   x7, 0x0020000C                     # Len 0x20, Load|Store
    or   x2, x6, x7
    li   x1, 55
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # Populate #1
    mv   x18, x27                            # traps so far

    li   x1, 55
    .insn i 0x0b, 0x5, x3, x1, 0            # bind c3 -- incarnation 1
    .insn r 0x5b, 0x0, 0x03, x19, x3, x0    # cgettag
    li   x8, 0
    li   x9, 0xABCD
    .insn r 0x0b, 0x3, 0x01, x9, x3, x8     # ocs.d c3 -- write a marker into arena1
    mv   x20, x27

    # --- incarnation 2, SAME slot, DIFFERENT frame
    la   x6, arena2
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, 55
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # Populate #2 -- gate reads the OLD retired
    mv   x21, x27                            # 0 new traps means it was ACCEPTED

    # --- THE MEASUREMENT: is incarnation 1's capability still live?
    li   x8, 0
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x3, x8    # ocl.d through c3
    mv   x22, x27
    # and does it reach arena1 -- the frame the descriptor no longer names?
    la   x11, arena1
    ld   x12, 0(x11)
    la   x13, arena2
    ld   x14, 0(x13)
check:
    bnez x18, fail                          # CONTROL 1: populate #1 accepted --
                                            # 0xFFFFFE -> 0xFFFFFF is a legal
                                            # increment and must still work
    li   x16, 1
    bne  x19, x16, fail                     # CONTROL 2: the bind minted
    bnez x20, fail                          # CONTROL 3: the write through it worked
    li   x16, 1
    bne  x21, x16, fail                     # THE FINDING: populate #2 must TRAP.
                                            # Before the fix this was 0.
    li   x16, 1
    bne  x22, x16, fail                     # and the old capability still works,
                                            # because nothing changed -- the
                                            # refusal was a refusal, not a redirect
    li   x16, 0xABCD
    bne  x10, x16, fail
    bne  x12, x16, fail                     # arena1 still holds the marker
    bnez x14, fail                          # arena2 was never written
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.balign 64
arena1:
    .space 64
arena2:
    .space 64
