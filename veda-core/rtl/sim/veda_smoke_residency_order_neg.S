.section .text
.global _start
// RTL-6 (DESIGN_02 Phase 2, increment 1): WHERE 0x0A SITS AMONG THE OTHER
// BIND-TIME CAUSES.
//
// The gate itself is tested by veda_smoke_residency. This test exists
// because a gate that fires correctly can still be wired at the wrong
// PRIORITY, and every one of those miswirings compiles clean and passes
// that other test. Three orderings, each with a fixture built so the
// correct and incorrect designs disagree at exactly one point.
//
// PART A -- 0x05 OUTRANKS 0x0A (object-not-found beats residency).
// A never-populated slot reads valid=0 AND resident=0, both from the ODT
// pre-zero. The residency gate carries an explicit `valid &&` conjunct
// precisely so this case reports "never existed" rather than "paged out".
// Drop that one conjunct and this fixture flips to 0x0A -- which would
// tell a pager to fetch an object that has no backing store anywhere,
// making an unrecoverable condition look recoverable and turning a clean
// failure into a retry loop.
//
// PART B -- 0x0A OUTRANKS 0x06 (residency beats wrong-owner).
// Object_ID=105 is seeded valid, non-resident, AND owned by hart 99. The
// residency gate precedes the mode match that produces the owner verdict,
// so residency must win. This is the ordering with real consequences:
// WRONG_OWNER is permanent and tells the handler to give up, RESIDENCY is
// serviceable and tells it to page in and retry. Both are true of this
// object; reporting the permanent one discards the recovery.
//
// PART C -- 0x09 OUTRANKS 0x0A (region residency beats object residency).
// Object_ID (2<<24)|8 is a non-resident object in a non-resident region.
// If the domain's table is paged out, the object's residency byte was
// never legitimately readable -- answering with 0x0A would be answering
// from a byte the core had no right to trust, and would send the handler
// to page in one object when what is actually missing is the whole table
// that describes it.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            // trap counter

    // ═══ PART A: never populated -> 0x05, NOT 0x0A ═══
    // Object_ID 107 is seeded nowhere and populated nowhere.
    li   x1, 107
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, x1
    li   t1, 1
    bne  x20, t1, fail
    li   t1, 0x05                          // cap_idx 0, so mtval == cause
    bne  x25, t1, fail
    li   x21, 0x600D

    // ═══ PART B: non-resident AND owned elsewhere -> 0x0A, NOT 0x06 ═══
    li   x1, 105
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, x1
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x2A                          // (cap_idx 1 << 5) | cause 0x0A
    bne  x25, t1, fail
    li   x22, 0x600D

    // Control for PART B, and it is what makes PART B mean anything: an
    // object that is owned elsewhere but IS resident must still report
    // 0x06. Without this line, a design that reported 0x0A for every
    // wrong-owner object would pass PART B and be badly wrong.
    li   x1, 60
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, x1
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0x46                          // (cap_idx 2 << 5) | cause 0x06
    bne  x25, t1, fail
    li   x23, 0x600D

    // ═══ PART C: non-resident object in a non-resident region -> 0x09 ═══
    li   x1, 2
    slli x1, x1, 24
    ori  x1, x1, 8                         // Object_ID = (2<<24)|8
    .insn i 0x0b, 0x5, x6, x1, 0           // veda.bind c6, x1
    li   t1, 4
    bne  x20, t1, fail
    li   t1, 0xC9                          // (cap_idx 6 << 5) | cause 0x09
    bne  x25, t1, fail
    li   x24, 0x600D

    // Control for PART C: a RESIDENT object in the same non-resident
    // region also reports 0x09. Pairing the two proves the region gate is
    // deciding both, rather than PART C having landed on 0x09 by accident.
    li   x1, 2
    slli x1, x1, 24
    ori  x1, x1, 7                         // Object_ID = (2<<24)|7
    .insn i 0x0b, 0x5, x7, x1, 0           // veda.bind c7, x1
    li   t1, 5
    bne  x20, t1, fail
    li   t1, 0xE9                          // (cap_idx 7 << 5) | cause 0x09
    bne  x25, t1, fail
    li   x26, 0x600D

    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x24, t1, fail
    bne  x26, t1, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    csrr t5, mcause
    li   t6, 0x18
    bne  t5, t6, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
fail:
    li   x30, 0xBAD
done:
    j    done
