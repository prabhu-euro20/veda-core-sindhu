.section .text
.global _start
// R67 -- the trap frame has an OWNER, not just a count. The RTL half.
//
// veda_trap_depth is pushed at ONE site (trap entry) and popped at TWO, and
// OCInvoke touches it nowhere -- so an OCRETURN by a principal that never
// trapped popped a frame it did not push. Measured on Sail: compartment D
// returned and compartment C's frame went from mepcc_length 0x40 to the
// unbounded sentinel. R12's poison does not catch it, because poison arms on a
// nested TRAP and no trap occurred.
// Every register by number.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x16, 0

    // authority object (Seal|Unseal)
    li   x1, 602
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    // compartment C: narrow code window
    la   x6, compC
    slli x6, x6, 32
    li   x7, 0x00400402
    or   x2, x6, x7
    li   x1, 600
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 601
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    // compartment D: a SECOND compartment the handler will call into
    la   x6, compD
    slli x6, x6, 32
    li   x7, 0x00400402
    or   x2, x6, x7
    li   x1, 603
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 604
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    // an unbounded sentry D returns through
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, 605
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8
    bne  x27, x0, done

    li   x1, 602
    .insn i 0x0b, 0x5, x7, x1, 0            // authority -> c7
    li   x1, 600
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 601
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7     // sealed C pair -> c3/c4
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7
    li   x1, 603
    .insn i 0x0b, 0x5, x8, x1, 0
    li   x1, 604
    .insn i 0x0b, 0x5, x9, x1, 0
    .insn r 0x5b, 0x1, 0x10, x10, x8, x7    // sealed D pair -> c10/c11
    .insn r 0x5b, 0x1, 0x10, x11, x9, x7
    li   x1, 605
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0   // csealentry c13 -- D's exit sentry
    bne  x27, x0, done

    csrr x18, 0x7C8                         // depth before anything: expect 0
    // R50 increment 2: this file predates the crossing's retain mask and
    // measures a different mechanism, so it declares RETAIN ALL. The burden
    // of proving the clear works sits on veda_smoke_r50i2_crossing_clear.S.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4     // ocinvoke -> C
    j    done
.balign 4
compC:
    csrr x19, 0x7C1                         // C's own PCC length -- CONTROL
    ecall                                   // depth 1, C's bounds saved
    j    done
.balign 4
compD:
    csrr x21, 0x7C8                         // depth inside D -- still 1?
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0    // ocreturn c13 -- D never trapped
    j    done
.balign 4
landing:
    csrr x22, 0x7C8                         // THE MEASUREMENT: depth now?
    csrr x23, 0x7C3                         // and is C's saved frame still there?
    j    check
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x20, 0x7C8                         // depth in the handler: expect 1
    csrr x24, 0x7C3                         // C's saved length
    // the handler narrows ITSELF by OCInvoke -- the case R12's own comment names
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x10, x11   // ocinvoke -> D
    j    done
check:
    bnez x18, done
    li   x14, 0x40
    bne  x19, x14, done
    li   x14, 1
    bne  x20, x14, done
    li   x14, 0x40
    bne  x24, x14, done
    li   x14, 1
    bne  x21, x14, done
    li   x14, 1
    bne  x22, x14, done                     // THE FINDING: D's OCRETURN must NOT
                                            // pop a frame it did not push
    li   x14, 0x40
    bne  x23, x14, done                     // and C's saved window must survive
    li   x25, 0x600D
    j    done
done:
1:
    j 1b
