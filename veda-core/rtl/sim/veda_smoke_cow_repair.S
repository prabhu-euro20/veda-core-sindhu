
.section .text
.global _start
// COPY-ON-WRITE, REPAIRED END TO END -- the fault is raised, identified,
// fixed, and the SAME store then succeeds.
//
// This is the test that decides whether the mechanism is usable rather than
// merely present. DESIGN_02's own rule: "a repair path that cannot repair would
// be motion without progress."
//
// THE HANDLER HARDCODES NOTHING. It reads mtval, splits out the cause and the
// capability index, asks the capability which OBJECT it names, and repairs THAT
// object. Until CGetObjectID existed, that middle step was impossible: a trap
// reported {cap_idx, cause} and no Object_ID, and the query family read every
// field of a capability except its name. The nearest thing to a pager in this
// corpus (vc_paging_full_cycle) hardcodes the Object_ID its handler repairs,
// because it had no other choice.
//
// mepc is deliberately NOT advanced. Copy-on-write repair means the faulting
// store must RUN AGAIN and succeed -- if the handler skipped it, the write the
// program asked for would silently never happen.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x28, 0                    // the Object_ID the handler will discover

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, 1
    li   x2, 0
    li   x3, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d -- plain write, works
    li   x21, 0x600D

    // ---- mark it copy-on-write
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1
    bne  x20, x0, fail

    // ---- the write that must fault, be repaired, and then SUCCEED
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d c0 -- faults, repairs, retries
    li   x6, 1
    bne  x20, x6, fail             // exactly one fault, then it went through
    li   x22, 0x600D

    // ---- the value really landed
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2
    li   x6, 0xF00D
    bne  x10, x6, fail
    li   x23, 0x600D

    // ---- and the handler found the right object WITHOUT being told
    li   x6, 1
    bne  x28, x6, fail
    li   x24, 0x600D

    li   x6, 0x600D
    bne  x21, x6, fail
    bne  x22, x6, fail
    bne  x23, x6, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    // Scratch is x16/x17/x18 -- RAW x-numbers, never ABI aliases. t3/t4/t5 are
    // x28/x29/x30, and x28 is this test's result register: the first draft used
    // them and the handler quietly erased the very Object_ID it had just gone to
    // the trouble of discovering. Fifth time this alias collision has cost this
    // project a debugging cycle.
    csrr x16, mcause
    li   x17, 0x18
    bne  x16, x17, fail
    csrr x25, mtval
    andi x16, x25, 0x1F            // cause
    li   x17, 0x0C
    bne  x16, x17, fail            // must be the COW fault, not 0x13
    srli x18, x25, 5               // capability index that faulted
    bnez x18, fail                 // this test faults through c0

    // ---- WHICH OBJECT? Ask the capability. Nothing here is hardcoded.
    .insn r 0x5b, 0x0, 0x07, x28, x0, x0   # cgetobjectid x28, c0

    // ---- repair THAT object: clear its copy-on-write mark
    li   x17, 0
    .insn r 0x0b, 0x1, 0x07, x16, x28, x17 # veda.odt.set.cow x28 <- 0

    addi x20, x20, 1
    // mepc is NOT advanced -- the faulting store must run again
    mret
fail:
    li   x30, 0xBAD

done:
    j    done
