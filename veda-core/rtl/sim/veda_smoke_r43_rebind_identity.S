.section .text
.global _start
// R43 -- "already-bound" was a precondition nobody enforced. The RTL half.
//
// Section 4 defines Rebind as refreshing an ALREADY-BOUND register, and neither
// the tag nor the Object_ID was checked -- so Rebind carried an Offset
// meaningful in object A onto object B's bounds. Closing it removes the LAST
// untagged sealedness read on either layer: $veda_rebind_sealed read the
// destination's otype with no tag conjunct, and every other sealedness consumer
// checks the tag first or conjoins it. Soft-fail, not a trap.
// Objects 208 and 209; the fixtures seed 1, 2, 60, 104, 105, 106, 108, 109,
// 257, 519 and 520 only. Every register by number.
.equ OBJ_A, 208
.equ OBJ_B, 209
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0

    la   x6, arena_a
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, OBJ_A
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, arena_b
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, OBJ_B
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, done

    // CONTROL 1: a genuine bind of A
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x3, x1, 0
    .insn r 0x5b, 0x0, 0x03, x18, x3, x0    // cgettag -- must be 1
    li   x8, 1
    bne  x18, x8, done
    .insn r 0x5b, 0x0, 0x00, x19, x3, x0    // cgetbase
    la   x9, arena_a
    bne  x19, x9, done

    // CONTROL 2: R43's POSITIVE arm -- rebinding the SAME object into a register
    // that is tagged and names it is a genuine refresh and must still succeed.
    // Without this, refusing every Rebind would pass both findings below.
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x3, x1, 2
    .insn r 0x5b, 0x0, 0x03, x20, x3, x0    // cgettag -- must still be 1
    li   x8, 1
    bne  x20, x8, done
    .insn r 0x5b, 0x0, 0x00, x21, x3, x0
    bne  x21, x9, done                      // and still A's Base

    // THE FINDING, part 1: a DIFFERENT object. Before the fix this succeeded and
    // carried an Offset meaningful in A onto B's bounds.
    li   x1, OBJ_B
    .insn i 0x0b, 0x5, x3, x1, 2
    .insn r 0x5b, 0x0, 0x03, x22, x3, x0    // cgettag -- must be 0
    bnez x22, done

    // THE FINDING, part 2: an UNTAGGED destination. c4 was never written.
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x4, x1, 2
    .insn r 0x5b, 0x0, 0x03, x23, x4, x0    // cgettag -- must be 0
    bnez x23, done

    // CONTROL 3: a refusal is a refusal, not a corruption -- a plain Bind into
    // either register still works afterwards.
    li   x1, OBJ_B
    .insn i 0x0b, 0x5, x4, x1, 0
    .insn r 0x5b, 0x0, 0x03, x24, x4, x0
    li   x8, 1
    bne  x24, x8, done
    .insn r 0x5b, 0x0, 0x00, x25, x4, x0
    la   x10, arena_b
    bne  x25, x10, done

    bne  x27, x0, done                      // and nothing trapped: Rebind SOFT-fails
    li   x26, 0x600D
    j    done
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
done:
1:
    j 1b
.section .data
.balign 64
arena_a:
    .space 64
arena_b:
    .space 64
