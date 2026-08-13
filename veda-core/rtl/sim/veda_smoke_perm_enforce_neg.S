.section .text
.global _start
// RTL-12: CAndPerm rights attenuation, ENFORCED -- closing a gap PROVEN to
// exist by experiment, not suspected.
//
// Deleting the store-permission term from all three of the RTL's store paths
// -- $veda_ocs_violation, $veda_ocsc_violation, $veda_atomic_violation --
// left the entire 73-test suite passing. Store permission was implemented and
// completely unverified in hardware. The load side was the same.
//
// WHY THIS IS A PREREQUISITE AND NOT TIDYING. DESIGN_02's copy-on-write
// mechanism plans to reuse the store-side violation as its COW fault. Building
// COW on a trap no test had ever fired would be building on sand, and the
// design doc says so in those words.
//
// WHY THE RTL NEEDS MORE PHASES THAN THE MODEL. Sail routes OCL/OCS through
// ONE shared helper (veda_check_access), so its own test covers the shared
// code by covering OCS.D. This file repeats the permission term in THREE
// separate expressions, one per store path, so three separate phases are
// needed. Same property, different number of sites -- the structural
// difference between a model that shares a helper and hardware that inlines
// the condition.
//
// Object_ID 1 is reset-seeded Base 0x80010000, Length 0x40, Perms 0x100C =
// Permit_Load (bit 2) | Permit_Store (bit 3) | Permit_NMC_Compute (bit 12).
//
// Phases 3 and 5 are what make this enforcement rather than a pair of trap
// assertions: they prove the attenuation is PRECISE -- it removes exactly the
// named right and leaves the other intact. An implementation that made an
// attenuated capability useless outright would pass phases 2 and 4 and fail
// these.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0                            // trap counter

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 1 -- full Perms

    // ═══ phase 1: positive control -- the full capability round-trips ═══
    li   x2, 0                             // offset
    li   x3, 0xABC
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2    // ocs.d c0, x2, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0, x2, x10
    li   x6, 0xABC
    bne  x10, x6, fail
    li   x22, 0x600D

    // ═══ phase 2: strip Permit_Store -> c1, then OCS.D must trap 0x13 ═══
    li   x6, 0xFFF7                        // clear bit 3, keep the rest
    .insn r 0x5b, 0x1, 0x17, x1, x0, x6    // candperm c1, c0, x6
    li   x3, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2    // ocs.d c1 -- must TRAP (1)
    mv   x23, x21                          // mtval = (1 << 5) | 0x13 = 0x33

    // ═══ phase 3: c1 must STILL load, and read the ORIGINAL value ═══
    // Two things at once: only the store right was removed, and the refused
    // store genuinely never reached memory.
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x1, x2   // ocl.d c1
    li   x6, 0xABC
    bne  x10, x6, fail                     // 0xDEAD here = the store landed
    li   x24, 0x600D

    // ═══ phase 4: strip Permit_Load -> c4, then OCL.D must trap 0x12 ═══
    li   x6, 0xFFFB                        // clear bit 2
    .insn r 0x5b, 0x1, 0x17, x4, x0, x6    // candperm c4, c0, x6
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x4, x2   // ocl.d c4 -- must TRAP (2)
    mv   x25, x21                          // mtval = (4 << 5) | 0x12 = 0x92

    // ═══ phase 5: c4 must STILL store -- attenuation is precise both ways ═══
    // Read back through the FULL capability, since c4 cannot load.
    li   x3, 0x5A5A
    .insn r 0x0b, 0x3, 0x01, x3, x4, x2    // ocs.d c4 -- must SUCCEED
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0
    li   x6, 0x5A5A
    bne  x10, x6, fail
    li   x26, 0x600D

    // ═══ phase 6: OCS.C is a SECOND store path with its own copy of the
    //     permission term, and its own chance to be missing it. ═══
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x0, x1, x2    // ocs.c c1(addr), x2, c0 -- TRAP (3)
    mv   x27, x21

    // ═══ phase 7: the Veda-Atomic path is the THIRD. ═══
    li   x3, 5
    .insn r 0x2b, 0x3, 0x00, x12, x1, x3   // veda.amoadd.d via c1 -- TRAP (4)
    mv   x28, x21

    // ═══ and the memory must still hold phase 5's value: three refused
    //     stores, none of which half-applied ═══
    li   x2, 0
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2   // ocl.d c0
    li   x6, 0x5A5A
    bne  x10, x6, fail
    li   x29, 0x600D

    // ═══ phase 8: the atomic path checks LOAD permission as well as store,
    //     and that term needs its own phase -- stripping store never
    //     exercises it. ═══
    li   x3, 5
    .insn r 0x2b, 0x3, 0x00, x13, x4, x3   // veda.amoadd.d via c4 -- TRAP (5)
    mv   x11, x21                          // expect (4 << 5) | 0x12 = 0x92

    // ═══ phase 9: CAndPerm must carry the GENERATION, and proving that needs
    //     an object whose generation is NOT zero. ═══
    // Object 1's generation is 0 and a capability register resets to 0, so a
    // capability that lost its generation entirely still compares equal and
    // the fault hides. Object 40 is destroyed once first, which bumps its
    // generation to 1, and only then does a lost generation become visible.
    // Found by predicting the mutant: with the carry removed, everything
    // above still passed.
    // The descriptor lives in x7 and STAYS there: an earlier draft built it in
    // x5 and also used x5 as the populate's rd, so the first populate
    // overwrote its own descriptor and the second ran on garbage.
    la   x7, array_g
    slli x7, x7, 32
    li   x9, 0x0008000C                    // Length 8, Perms Load|Store.
                                           // 0x...0004 is Load ONLY -- copied
                                           // from a load-only fixture, it made
                                           // this phase's own ocs.d trap 0x13,
                                           // the very check under test.
    or   x7, x7, x9
    li   x1, 40
    .insn r 0x0b, 0x0, 0x03, x9, x1, x7    // populate 40
    li   x1, 40
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0    // destroy 40 -- generation -> 1
    li   x1, 40
    .insn r 0x0b, 0x0, 0x03, x9, x1, x7    // repopulate 40 (generation stays 1)

    li   x1, 40
    .insn i 0x0b, 0x5, x5, x1, 0           // veda.bind c5, 40 -- cap.gen = 1
    li   x2, 0
    li   x3, 0x7C7C
    .insn r 0x0b, 0x3, 0x01, x3, x5, x2    // ocs.d c5 -- must SUCCEED
    li   x6, 0xFFF7
    .insn r 0x5b, 0x1, 0x17, x6, x5, x6    // candperm c6, c5, x6 (strip store)
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x6, x2   // ocl.d c6 -- must SUCCEED, no trap
    li   x6, 0x7C7C
    bne  x10, x6, fail                     // a lost generation traps 0x02 here
    li   x14, 0x600D

    // ---- final checks
    li   x6, 0x33
    bne  x23, x6, fail                     // OCS.D store violation, cap_idx 1
    li   x6, 0x92
    bne  x25, x6, fail                     // OCL.D load violation, cap_idx 4
    li   x6, 0x92
    bne  x11, x6, fail                     // atomic load violation, cap_idx 4
    li   x6, 5
    bne  x20, x6, fail                     // exactly five traps
    li   x6, 0x600D
    bne  x22, x6, fail
    bne  x24, x6, fail
    bne  x26, x6, fail
    bne  x29, x6, fail
    bne  x14, x6, fail
    li   x30, 0xD09E
    j    done

.balign 4
// Scratch is x16/x17 -- raw x-numbered registers. t5/t6 are x30/x31 and x30
// is the result register here.
trap_handler:
    csrr x16, mcause
    li   x17, 0x18                         // E_Extension -- every Veda hard trap
    bne  x16, x17, fail
    csrr x21, mtval
    addi x20, x20, 1
    csrr x16, mepc                         // resume past the refused access
    addi x16, x16, 4
    csrw mepc, x16
    mret
fail:
    li   x30, 0xBAD
done:
    j    done

.section .data
.balign 32
array_g:
    .dword 0
    .dword 0
