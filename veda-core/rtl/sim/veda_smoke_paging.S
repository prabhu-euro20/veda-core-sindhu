.section .text
.global _start
// RTL-6c (DESIGN_02 Phase 2, increment 2): the PAGE-OUT / PAGE-IN CYCLE,
// end to end, plus what page-in preserves.
//
// PART A -- THE FULL CONTRACT. Mint an object, use it, page it out, watch
// the held capability go stale, re-Bind, page it in AT A DIFFERENT FRAME,
// and use it again at the new location. Two real linker-allocated buffers,
// so "the object moved" is a fact about addresses rather than an
// assertion about a field.
//
// The stale-capability step is the security claim. Page-out BUMPS
// generation, which is what invalidates every outstanding capability --
// that is the cached-Base contract DESIGN_02 chose deliberately over the
// alternative of never caching Base and paying a table read on every
// access forever. Paging is therefore NOT transparent here, by design: a
// holder whose object was paged out sees a trap and must re-Bind.
//
// PART B -- GENERATION IS PRESERVED ACROSS A PAGE-IN, measured by
// COUNTING. `generation` is architecturally unreadable, so the only
// available observable is the saturation refusal boundary. Object_ID 108
// is seeded at 0xFFFFFD, TWO steps below the ceiling:
//     preserving -- FD->FE, FE->FF, then refused  = TWO page-outs succeed
//     bumping    -- FD->FE, page-in bumps to FF   = ONE succeeds
// A fixture ONE step below would not discriminate: a wrong bump would
// saturate to 0xFFFFFF, which is indistinguishable from correct
// preservation. The mutation hides inside the saturation.
//
// PART C -- owner_hart IS PRESERVED. Object_ID 109 is owned by hart 0x63,
// so Bind's own 0x06 refusal makes ownership observable in a single-hart
// core. Page-out is gated on authority, not ownership, so a pager may
// evict an object it does not own; if page-in reset owner_hart, any hart
// could then claim it. Object theft by triggering a page fault.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0                            // trap counter

    // ═══ PART A: mint Object_ID 103 at frame_a and use it ═══
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x000C                    // Length 0x100, Perms Load|Store
    csrw 0x7C4, x6                         // veda_attr
    la   x7, frame_a
    li   x1, 103
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    // veda.odt.populate.fast

    li   x1, 103
    .insn i 0x0b, 0x5, x2, x1, 0           // veda.bind c2, x1
    .insn r 0x5b, 0x0, 0x00, x21, x2, x0   // cgetbase x21, c2 -- old Base
    li   x3, 0
    li   x4, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x4, x2, x3    // ocs.d c2, x3, x4
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x8, x2, x3    // ocl.d c2, x3, x8
    li   x9, 0xF00D
    bne  x8, x9, fail                      // round-tripped before paging
    li   x22, 0x600D

    // ---- page it out
    // x10 is PRE-LOADED with a sentinel. Without that the rd=0 assertion
    // is vacuous -- x10 reads 0 at reset, so it passes whether or not the
    // instruction wrote anything. Mutation testing found exactly that:
    // deleting the rd write-back left all 69 tests passing.
    li   x10, 0xDEAD
    li   x1, 103
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // veda.odt.page.out
    bne  x20, x0, fail                     // must NOT trap
    bne  x10, x0, fail                     // rd = 0 on success
    li   x23, 0x600D

    // ---- the held capability is now stale: generation was bumped, so the
    //      dereference fails on 0x02, NOT on residency. That ordering is
    //      correct and deliberate -- see the deref test's own note.
    .insn r 0x0b, 0x3, 0x00, x8, x2, x3    // ocl.d c2 -- must trap
    li   x9, 1
    bne  x20, x9, fail
    li   x9, 0x42                          // (cap_idx 2 << 5) | cause 0x02
    bne  x25, x9, fail
    li   x24, 0x600D

    // ---- re-Binding a paged-out object is refused with RESIDENCY, which
    //      is what tells a pager the object is serviceable rather than gone
    li   x1, 103
    .insn i 0x0b, 0x5, x11, x1, 0          // veda.bind c11, x1
    li   x9, 2
    bne  x20, x9, fail
    li   x9, 0x16A                         // (cap_idx 11 << 5) | cause 0x0A
    bne  x25, x9, fail
    li   x26, 0x600D

    // ---- page it back in at a DIFFERENT frame
    la   x7, frame_b
    li   x10, 0xDEAD
    li   x1, 103
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // veda.odt.page.in
    li   x9, 2
    bne  x20, x9, fail                     // no new trap
    bne  x10, x0, fail                     // rd = 0 on success
    li   x27, 0x600D

    // ---- re-Bind now succeeds, and the object really MOVED
    li   x1, 103
    .insn i 0x0b, 0x5, x12, x1, 0          // veda.bind c12, x1
    .insn r 0x5b, 0x0, 0x00, x28, x12, x0  // cgetbase x28, c12 -- new Base
    beq  x28, x21, fail                    // MUST differ from the old Base
    li   x29, 0x600D

    // ---- and it works at the new location
    li   x4, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x4, x12, x3   // ocs.d c12, x3, x4
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x8, x12, x3   // ocl.d c12, x3, x8
    li   x9, 0xBEEF
    bne  x8, x9, fail
    li   x9, 2
    bne  x20, x9, fail                     // still no new trap
    li   x30, 0x600D

    // ═══ PART B: generation preserved, by counting page-outs ═══
    li   x1, 108                           // seeded at generation 0xFFFFFD
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out #1 -- FD -> FE
    li   x9, 2
    bne  x20, x9, fail
    la   x7, frame_c
    li   x1, 108
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // page-in -- must PRESERVE FE
    bne  x20, x9, fail
    li   x1, 108
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out #2 -- FE -> FF
    bne  x20, x9, fail                     // THE ASSERTION: still no trap
    li   x31, 0x600D
    la   x7, frame_d
    li   x1, 108
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // page-in again
    bne  x20, x9, fail
    li   x1, 108
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out #3 -- NOW refused
    li   x9, 3
    bne  x20, x9, fail
    li   x9, 2
    bne  x25, x9, fail                     // mcause 2 = Illegal_Instruction
    li   x13, 0x600D

    // ═══ PART C: owner_hart preserved across a paging cycle ═══
    li   x1, 109                           // owned by hart 0x63
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, x1 -- 0x06
    li   x9, 4
    bne  x20, x9, fail
    li   x9, 0x06                          // cap_idx 0, so mtval == cause
    bne  x25, x9, fail

    li   x1, 109
    .insn r 0x0b, 0x1, 0x05, x10, x1, x0   // page-out -- allowed (authority)
    la   x7, frame_e
    li   x1, 109
    .insn r 0x0b, 0x0, 0x05, x10, x1, x7   // page-in
    li   x9, 4
    bne  x20, x9, fail                     // neither trapped

    // THE ASSERTION: ownership survived, so Bind must STILL refuse 0x06.
    // Had page-in reset owner_hart, this Bind would SUCCEED -- the object
    // would have been stolen by paging it.
    li   x1, 109
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, x1
    li   x9, 5
    bne  x20, x9, fail
    li   x9, 0x06
    bne  x25, x9, fail
    li   x14, 0x600D

    li   x9, 0x600D
    bne  x22, x9, fail
    bne  x23, x9, fail
    bne  x24, x9, fail
    bne  x26, x9, fail
    bne  x27, x9, fail
    bne  x29, x9, fail
    bne  x30, x9, fail
    bne  x31, x9, fail
    bne  x13, x9, fail
    bne  x14, x9, fail
    li   x15, 0xD09E
    j    done

.balign 4
// Scratch is x16/x17 -- deliberately raw x-registers, not ABI aliases.
// t5/t6 are x30/x31 and both are result registers here; naming the alias
// hides that collision one ABI table away, which has now cost this project
// four separate debugging cycles.
trap_handler:
    csrr x16, mcause
    li   x17, 0x18
    beq  x16, x17, veda_trap
    mv   x25, x16                          // ordinary trap: record mcause
    j    resume
veda_trap:
    csrr x25, mtval                        // Veda trap: record mtval
resume:
    addi x20, x20, 1
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x15, 0xBAD
done:
    j    done

.section .data
.balign 32
frame_a: .zero 0x100
.balign 32
frame_b: .zero 0x100
.balign 32
frame_c: .zero 0x100
.balign 32
frame_d: .zero 0x100
.balign 32
frame_e: .zero 0x100
