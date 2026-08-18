.section .text
.global _start
// RTL-17: THE POLICY WRITE PATH -- veda.odt.set.domain
//
// The first instruction here that changes an ODT entry WITHOUT changing what
// the object is. Every other writer bumps the generation and kills every
// outstanding capability -- right for them, because they change Base, Length
// or existence, so the object really has become a different object.
//
// PHASE 2 IS THE WHOLE POINT. Narrowing who may bind an object must NOT
// invalidate the capabilities held by those still entitled to it, or declaring
// a sharing rule destroys the sharing it describes. If phase 2 ever fails, this
// instruction has become an expensive Populate and both copy-on-write and
// per-object bind authority are blocked again.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0

    // ═══ phase 1: an ordinary bind and round-trip ═══
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 1
    li   x2, 0
    li   x3, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    // ocs.d c0, 0, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d
    li   x6, 0xBEEF
    bne  x10, x6, fail
    li   x21, 0x600D

    // ═══ phase 2: narrow it, then REUSE THE SAME CAPABILITY ═══
    li   x1, 1
    // R62 (D6): this named domain 5, and set.domain now REFUSES it -- region
    // 5 has rt_valid = 0, it has never been configured, so it is not a
    // principal but a principal that DOES NOT EXIST YET. Every use of
    // set.domain in the whole corpus, on both layers, named such a domain --
    // three tests, three nonexistent principals -- which is exactly why the
    // missing check was invisible. Region 1 is real, configured and resident,
    // so the test now asserts what it always meant.
    li   x4, 1
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4    // veda.odt.set.domain 1 -> 1
    bne  x20, x0, fail                     // the write must not trap
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d through the OLD c0
    li   x6, 0xBEEF
    bne  x10, x6, fail                     // a bumped generation traps 0x02 here
    bne  x20, x0, fail
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    // and it can still STORE
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2
    li   x6, 0xF00D
    bne  x10, x6, fail
    li   x22, 0x600D

    // ═══ phase 3: boot is in no compartment, so it may still bind ═══
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, 1 -- must SUCCEED
    .insn r 0x5b, 0x0, 0x03, x11, x1, x0   // cgettag
    li   x6, 1
    bne  x11, x6, fail
    bne  x20, x0, fail
    li   x23, 0x600D

    // ═══ phase 4: widen back to ANY, proving the field is really read ═══
    li   x1, 1
    li   x4, 0xFFFFF
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0
    .insn r 0x5b, 0x0, 0x03, x12, x2, x0
    li   x6, 1
    bne  x12, x6, fail
    bne  x20, x0, fail
    li   x24, 0x600D

    li   x6, 0x600D
    bne  x21, x6, fail
    bne  x22, x6, fail
    bne  x23, x6, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    csrr x16, mcause
    li   x17, 0x18
    bne  x16, x17, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x30, 0xBAD
done:
    j    done
