#include "veda_priv_macros.h"
.section .text
.global _start
// RTL-6c (DESIGN_02 Phase 2, increment 2): WHAT THE PAGING PAIR REFUSES.
//
// A separate test from the working cycle because Sail-side mutation
// testing showed exactly where the value of this pair lives: of six
// mutants, the four that survived a suite proving the mechanism WORKS were
// all refusals or preservations. For a security primitive, what it
// declines to do is the product.
//
// PART A -- PAGE-IN MUST REFUSE A LIVE, RESIDENT OBJECT. The sharpest one.
// Page-in preserves generation by design, which is what lets a paged-out
// object return without killing its capabilities. Turned against a LIVE
// object that same property is the attack: an authorized pager could
// repoint a live object's Base at memory of its choosing while every
// outstanding capability kept validating, and nothing would signal the
// move. The contrast is exact -- doing the same through ODT-Populate BUMPS
// generation, killing every capability and making the relocation loud.
//
// PART B -- PAGE-OUT MUST REFUSE AN ALREADY-PAGED-OUT OBJECT. A second
// page-out burns one of the 2^24 generations the slot will ever have and
// invalidates precisely the capabilities a pending page-in was about to
// serve.
//
// PART C -- THE SATURATION REFUSAL, the security core. `generation`
// saturates at 0xFFFFFF rather than wrapping, so at the ceiling the bump
// becomes a silent no-op: page-out would clear residency while
// invalidating NOTHING, and a later page-in would restore residency at a
// NEW frame while every outstanding capability still matched, each
// computing its address from its own stale cached Base -- reading and
// writing a freed frame now owned by someone else. Object_ID 106 is seeded
// ONE step below the ceiling and driven there by the real instruction
// sequence rather than by a hand-placed state.
//
// PART D -- BOTH REFUSE WITHOUT AUTHORITY. veda.droppriv first, then both
// instructions must be refused outright. Paging is the power to relocate
// any object in the system; unauthorized access to it is total.
//
// Every part also asserts the refusal did not HALF-APPLY. State left
// behind by a refused instruction is worse than the refusal itself.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0                            // trap counter

    // ---- build a live, resident object at frame_old
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x000C
    csrw 0x7C4, x6
    la   x7, frame_old
    li   x1, 112
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // veda.odt.populate.fast

    li   x1, 112
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, x1
    .insn r 0x5b, 0x0, 0x00, x21, x2, x0   // cgetbase x21 -- the live Base
    li   x3, 0
    li   x4, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x4, x2, x3    // ocs.d c2, x3, x4
    li   x22, 0x600D

    // ═══ PART A: page-in a LIVE object at a different frame -- REFUSED ═══
    la   x7, frame_new
    li   x1, 112
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // veda.odt.page.in
    li   x9, 1
    bne  x20, x9, fail
    li   x9, 2                             // mcause 2 = Illegal_Instruction
    bne  x25, x9, fail
    li   x23, 0x600D

    // ---- A did not half-apply: the object has NOT moved, and the
    //      capability held across it still reads what it stored
    li   x1, 112
    .insn i 0x0b, 0x5, x11, x1, 0          // veda.bind c11, x1
    .insn r 0x5b, 0x0, 0x00, x12, x11, x0  // cgetbase x12, c11
    bne  x12, x21, fail                    // still at frame_old
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x8, x2, x3    // ocl.d c2 -- still valid
    li   x9, 0xF00D
    bne  x8, x9, fail                      // generation untouched, data intact
    li   x24, 0x600D

    // ═══ PART B: page out once (legal), then again (refused) ═══
    li   x1, 112
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // veda.odt.page.out -- SUCCEEDS
    li   x9, 1
    bne  x20, x9, fail                     // still exactly one trap
    li   x26, 0x600D

    li   x1, 112
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // AGAIN -- must be REFUSED
    li   x9, 2
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail
    li   x27, 0x600D

    // ---- B did not half-apply: the object is still merely paged out, so
    //      a Bind still reports RESIDENCY rather than anything else
    li   x1, 112
    .insn i 0x0b, 0x5, x13, x1, 0          // veda.bind c13, x1
    li   x9, 3
    bne  x20, x9, fail
    li   x9, 0x1AA                         // (cap_idx 13 << 5) | cause 0x0A
    bne  x25, x9, fail
    li   x28, 0x600D

    // ═══ PART C: the saturation refusal ═══
    // Object_ID 106 is seeded at generation 0xFFFFFE. One page-out is
    // legal and takes it to the ceiling; the next must fail closed.
    li   x1, 106
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out -- FE -> FF, SUCCEEDS
    li   x9, 3
    bne  x20, x9, fail
    la   x7, frame_sat
    li   x1, 106
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // page-in -- restores residency
    bne  x20, x9, fail
    li   x29, 0x600D

    li   x1, 106
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out AT the ceiling -- REFUSED
    li   x9, 4
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail
    li   x30, 0x600D

    // ---- C did not half-apply: residency was NOT cleared, so the object
    //      is still usable. This is the assertion that matters -- a
    //      refusal that still cleared residency would have produced
    //      exactly the {valid, non-resident, saturated} state whose
    //      page-in is the use-after-free.
    li   x1, 106
    .insn i 0x0b, 0x5, x14, x1, 0          // veda.bind c14, x1 -- must SUCCEED
    li   x9, 4
    bne  x20, x9, fail                     // no new trap
    .insn r 0x5b, 0x0, 0x03, x15, x14, x0  // cgettag x15, c14
    li   x9, 1
    bne  x15, x9, fail                     // a live, usable capability
    li   x31, 0x600D

    // ═══ PART D: no authority, no paging ═══
    // The page-out half needs a LIVE, RESIDENT object, and that detail is
    // the whole test. The first version of this part used Object_ID 112,
    // which PART B had already paged out -- so page-out refused it on
    // residency regardless of authority, and deleting the authority gate
    // changed nothing observable. Mutation testing caught it: removing
    // page-out's authority term left all 69 tests passing while removing
    // page-in's did not. A negative test has to make the condition it
    // names the ONLY reason for the refusal.
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x000C
    csrw 0x7C4, x6
    la   x7, frame_auth
    li   x1, 113
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // populate.fast -- live, resident
    li   x9, 4
    bne  x20, x9, fail                     // still authorized here

    // R79 -- THIS FILE OBSERVES RESIDENCY FROM USER BY BINDING 113 BY NAME
    // (line 184 below), as SCAFFOLDING for its real subject: that a refused
    // page-out did not half-apply. Ambient root is now Machine-or-ODA only, and
    // a privilege drop leaves the identity at the reset sentinel, so a bare
    // User-mode bind of a boot-owned object is refused. The object is therefore
    // DECLARED shareable here, at Machine, before the drop -- R52's own doctrine
    // that sharing is a declaration and not a default. It changes nothing about
    // what this file measures: residency is unaffected by owner_domain.
    li   x1, 113
    li   x9, 0xFFFFF                       // VEDA_DOMAIN_ANY
    .insn r 0x0b, 0x1, 0x06, x5, x1, x9    // set.domain 113 -> ANY

    VEDA_DROP_TO_USER(x1, x9)   // R36: the architected drop -- mstatus.MPP=U then mret

    li   x1, 113                           // live and resident: the ONLY
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // objection is authority
    li   x9, 5
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail
    li   x1, 112                           // paged out: only authority again
    la   x7, frame_new
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // page-in -- REFUSED
    li   x9, 6
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail
    li   x18, 0x600D

    // ---- and the refused page-out did not half-apply: 113 is still
    //      resident, so an unauthorized caller could not evict anything
    li   x1, 113
    .insn i 0x0b, 0x5, x6, x1, 0           // veda.bind c6, x1 -- must SUCCEED
    li   x9, 6
    bne  x20, x9, fail
    .insn r 0x5b, 0x0, 0x03, x8, x6, x0    // cgettag x8, c6
    li   x9, 1
    bne  x8, x9, fail
    li   x14, 0x600D

    li   x9, 0x600D
    bne  x22, x9, fail
    bne  x23, x9, fail
    bne  x24, x9, fail
    bne  x26, x9, fail
    bne  x27, x9, fail
    bne  x28, x9, fail
    bne  x29, x9, fail
    bne  x30, x9, fail
    bne  x31, x9, fail
    bne  x18, x9, fail
    bne  x14, x9, fail
    li   x19, 0xD09E
    j    done

.balign 4
trap_handler:
    csrr x16, mcause
    li   x17, 0x18
    beq  x16, x17, veda_trap
    mv   x25, x16                          // ordinary trap: mcause (2)
    j    resume
veda_trap:
    csrr x25, mtval                        // Veda trap: the mtval word
resume:
    addi x20, x20, 1
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x19, 0xBAD
done:
    j    done

.section .data
.balign 32
frame_old: .zero 0x100
.balign 32
frame_new: .zero 0x100
.balign 32
frame_sat: .zero 0x100
.balign 32
frame_auth: .zero 0x100
