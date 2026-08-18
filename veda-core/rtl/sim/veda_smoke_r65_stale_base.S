.section .text
.global _start
// R65 -- an authority test against a Base the object has LEFT. The RTL half.
//
// set.cow and set.domain authorize a delegated actor with the ODA window test
// on old_entry.Base, and neither required residency. Page-out preserves Base as
// a value the Sail source's own comment calls "stale, and unreachable", because
// freeing the frame is the point of eviction. So for a paged-out object the gate
// asks about the frame the object HAS LEFT.
//
// Measured end to end on Sail before the fix, from User with an ODA covering
// ONLY victim_frame: the set.domain retired, the pager restored the victim at
// new_frame, and cgetbase returned 0x80000240 -- a frame the attacker's window
// never covered, reached through a capability bind consults no ODA to mint.
//
// Every register by number. x27 traps, x26 mtval, x17 handler temp, x16 phase.
.equ VICTIM, 510
.equ ODAOBJ, 511
.equ OUTOBJ, 512
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x16, 0
    li   x18, 0
    li   x19, 0
    li   x20, 0

    // ---- M: the victim object, living in victim_frame
    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x0040000C                     // Len 64, Load|Store
    or   x2, x6, x7
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, done

    // ---- M: a SECOND object living OUTSIDE the attacker's window, as the control
    la   x6, other_frame
    slli x6, x6, 32
    li   x7, 0x0040000C
    or   x2, x6, x7
    li   x1, OUTOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, done

    // ---- M: the delegated authority, scoped to victim_frame ONLY
    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x00400080                     // Len 64, PERM_ACCESS_SYSTEM_REGISTERS
    or   x2, x6, x7
    li   x1, ODAOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, ODAOBJ
    .insn i 0x0b, 0x5, x1, x1, 0            // bind c1
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0     // ospecialrw c2, c1 -- ODA := c1
    bne  x27, x0, done

    // ---- M: evict the victim. Base stays victim_frame and is now, by the
    //        model's own comment, "stale, and unreachable".
    li   x1, VICTIM
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0     // page.out VICTIM
    bne  x27, x0, done
    li   x18, 0x600D

    // ---- drop to User, the architected way (R36)
    li   x7, 0x1800
    csrc mstatus, x7
    la   x8, umode
    csrw mepc, x8
    mret
.balign 4
umode:
    // ---- THE MEASUREMENT: retarget the policy of an object that is NOT THERE,
    //      authorized by a window test on the frame it used to occupy.
    li   x1, VICTIM
    li   x4, 1
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4     // set.domain VICTIM -> 1
    mv   x19, x27                            // 0 = the write was ACCEPTED

    // ---- CONTROL: the same actor, the same instruction, an object whose Base
    //      its ODA does not cover. This must be REFUSED, or the gate is simply
    //      absent and the measurement above means nothing.
    li   x1, OUTOBJ
    li   x4, 1
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    mv   x20, x27
    li   x16, 1
    ecall                                    // back to M
.balign 4
mphase2:
    // ---- M: the pager restores the victim to a DIFFERENT frame -- one the
    //      attacker's ODA never covered.
    la   x9, new_frame
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x05, x5, x1, x9     // page.in VICTIM at new_frame
    mv   x21, x27
    li   x1, VICTIM
    .insn i 0x0b, 0x5, x3, x1, 0            // bind c3, VICTIM
    .insn r 0x5b, 0x0, 0x00, x22, x3, x0    // cgetbase -- new_frame?
    la   x23, new_frame
    xor  x24, x22, x23
    seqz x24, x24
check:
    li   x10, 1
    bne  x19, x10, done                     // THE FINDING: the User set.domain on
                                            // the PAGED-OUT victim must TRAP
    li   x10, 2
    bne  x20, x10, done                     // CONTROL: the out-of-window write is
                                            // still refused -- the pre-existing
                                            // gate is untouched
    li   x10, 3
    bne  x21, x10, done                     // page.in still works and added no trap
    li   x10, 1
    bne  x24, x10, done                     // and the object really moved to a frame
                                            // the attacker never covered
    li   x25, 0x600D
    j    done
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    li   x17, 1
    beq  x16, x17, back_to_m
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
back_to_m:
    li   x16, 0
    li   x17, 0x1800
    csrs mstatus, x17                        // MPP := M
    la   x17, mphase2
    csrw mepc, x17
    mret
done:
1:
    j 1b
.section .data
.balign 64
victim_frame:
    .space 64
other_frame:
    .space 64
new_frame:
    .space 64
