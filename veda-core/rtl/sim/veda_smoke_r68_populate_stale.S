.section .text
.global _start
// R68 -- R65's rule reaches five sites, not two. The RTL half.
//
// $veda_oda_denies_old tests old_entry.Base, and page-out preserves that Base as
// a value the model calls "stale, and unreachable". R65 installed the residency
// term at set.cow and set.domain; the same test authorizes at seven sites.
// Measured on Sail: from User with an ODA covering only the freed frame, a
// Populate over the paged-out victim was ACCEPTED and the identical instruction
// against an out-of-window object was refused.
// Every register by number.
// RTL-safe Object_IDs: the RTL indexes with local[7:0], so 512 would alias
// object 0. The fixtures seed 1, 2, 60, 104, 105, 106, 108, 109, 257, 519, 520.
.equ VICTIM, 230
.equ ODAOBJ, 231
.equ OUTOBJ, 232
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
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     // POPULATE the victim at the frame it left
    mv   x19, x27                            // 0 = the write was ACCEPTED

    // ---- CONTROL: the same actor, the same instruction, an object whose Base
    //      its ODA does not cover. This must be REFUSED, or the gate is simply
    //      absent and the measurement above means nothing.
    li   x1, OUTOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
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
    bne  x19, x10, done                     // THE FINDING: must TRAP
    li   x10, 2
    bne  x20, x10, done                     // CONTROL: still refused out of window
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
