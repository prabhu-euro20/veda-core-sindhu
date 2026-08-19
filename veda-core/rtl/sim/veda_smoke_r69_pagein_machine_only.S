.section .text
.global _start
// R69 -- page-in is Machine-only, and both ODA window tests are deleted.
// The gate already refused !valid || resident, so every delegated execution was
// a non-resident one. Page-in's first ODA conjunct was an evictor test by proxy
// through an address, and the proxy decays the instant the frame becomes
// reallocatable. RTL-safe Object_IDs: local[7:0] indexing.
// Every register by number.
.equ VICTIM, 240
.equ ODAOBJ, 241
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x16, 0

    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x0040000C
    or   x2, x6, x7
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    // an ODA covering BOTH frames -- the strongest window a delegate could hold
    la   x6, victim_frame
    slli x6, x6, 32
    li   x7, 0x01000080
    or   x2, x6, x7
    li   x1, ODAOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, ODAOBJ
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0     // ospecialrw -- ODA := c1
    li   x1, VICTIM
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0     // page.out
    bne  x27, x0, done
    li   x18, 0x600D

    li   x7, 0x1800
    csrc mstatus, x7
    la   x8, umode
    csrw mepc, x8
    mret
.balign 4
umode:
    // THE FINDING: a delegated actor whose ODA covers BOTH the frame the victim
    // left and the frame it would land in. Before R69 this was ACCEPTED.
    la   x9, new_frame
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x05, x5, x1, x9     // page.in
    mv   x19, x27
    li   x16, 1
    ecall
.balign 4
mphase2:
    // CONTROL: Machine can still page it in. A rule that stranded the object
    // would be a bug, not a fix.
    la   x9, new_frame
    li   x1, VICTIM
    .insn r 0x0b, 0x0, 0x05, x5, x1, x9
    mv   x20, x27
    li   x1, VICTIM
    .insn i 0x0b, 0x5, x3, x1, 0            // bind -- it is usable again
    .insn r 0x5b, 0x0, 0x03, x21, x3, x0    // cgettag
    .insn r 0x5b, 0x0, 0x00, x22, x3, x0    // cgetbase
check:
    li   x10, 0x600D
    bne  x18, x10, done
    li   x10, 1
    bne  x19, x10, done                     // THE FINDING: the User page.in must TRAP
    li   x10, 2
    bne  x20, x10, done                     // CONTROL: Machine still can -- not stranded
    li   x10, 1
    bne  x21, x10, done
    la   x11, new_frame
    bne  x22, x11, done
    li   x23, 0x600D
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
    csrs mstatus, x17
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
new_frame:
    .space 64
