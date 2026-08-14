.section .text
.global _start
// RTL-16 (R18): THE BOUNDS CHECK MUST NOT WRAP.
//
// The check was `(offset + 8) <= Length` computed in 64 bits, with offset a
// full attacker-chosen GPR. offset = 0xFFFFFFFFFFFFFFF8 wraps offset+8 to 0,
// "0 <= Length" passes, and the address -- also a modular 64-bit add -- lands
// at Base-8. Every other term of the check is satisfied by an ordinary
// capability, so the access retires silently and reads and WRITES the bytes
// below the object. In a packed allocator those are the neighbour's.
//
// This is an out-of-object read AND write reached with a perfectly valid
// capability -- the object-centric pillar failing on the one path that is
// supposed to embody it. Sail refuses it, because its arithmetic is
// arbitrary-precision and cannot wrap.
//
// PART A -- offset -8 must TRAP (bounds violation, cause 0x01)
// PART B -- offset -16 likewise, and the capability-width form too
// PART C -- the control: ordinary in-bounds access still works, so PART A
//           cannot pass by the check having been broken for everyone.
_start:
    la   x1, trap_handler
    csrw mtvec, x1
    li   x20, 0

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 1 (Base .., Len 0x40)

    // ═══ PART C: the control, first -- a normal store/load round-trips ═══
    li   x2, 0
    li   x3, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    // ocs.d c0, 0, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0, 0, x10
    li   x6, 0xC0FFEE
    bne  x10, x6, fail
    li   x21, 0x600D

    // ═══ PART A: offset -8. offset+8 wraps to 0 and the old check passed ═══
    li   x2, -8
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0, -8 -- must TRAP (1)
    li   x9, 1
    bne  x20, x9, fail
    li   x9, 0x01                          // (cap_idx 0 << 5) | 0x01 bounds
    bne  x25, x9, fail
    bnez x10, fail                         // and nothing was loaded

    // the WRITE direction matters more than the read
    li   x3, 0xBAD0BAD
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    // ocs.d c0, -8 -- must TRAP (2)
    li   x9, 2
    bne  x20, x9, fail
    li   x22, 0x600D

    // ═══ PART B: offset -16, and the capability-width form ═══
    li   x2, -16
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0, -16 -- must TRAP (3)
    li   x9, 3
    bne  x20, x9, fail
    // -32, not -16: the 32-byte alignment gate is checked BEFORE bounds, so
    // -16 traps as misaligned and never reaches the bounds term at all. The
    // first draft used -16 and the bounds mutant survived because of it --
    // the test trapped, just for the wrong reason.
    li   x2, -32
    .insn r 0x0b, 0x4, 0x00, x11, x0, x2   // ocl.c c11, c0, -32 -- must TRAP (4)
    li   x9, 4
    bne  x20, x9, fail
    li   x23, 0x600D

    // ═══ and the object itself is untouched: the control value survives ═══
    li   x2, 0
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0, 0
    li   x6, 0xC0FFEE
    bne  x10, x6, fail                     // 0xBAD0BAD here = the store landed
    li   x24, 0x600D

    li   x9, 0x600D
    bne  x21, x9, fail
    bne  x22, x9, fail
    bne  x23, x9, fail
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
