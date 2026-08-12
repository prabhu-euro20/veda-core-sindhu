.section .text
.global _start
// RTL-6b (DESIGN_02 Phase 2, increment 1): the DEREFERENCE-SIDE object
// residency check, and its POSITION at the end of the cause chain.
//
// c11 is reset-seeded pointing at Object_ID 104 -- valid, NOT resident --
// with every other field built to pass: matching generation, unsealed,
// Load|Store permissions, Offset 0 well inside a 0x40 Length. So residency
// is the only remaining objection, which is what makes the cause code a
// clean measurement rather than a coincidence.
//
// PART A -- the check exists at all, on the ordinary load/store path.
// Without the dereference-side term, an OCL.D through c11 would SUCCEED:
// it would compute its address from the capability's CACHED Base and read
// a frame the object no longer occupies. That is the use-after-free this
// increment exists to prevent, and it is reachable without any privileged
// instruction.
//
// PART B -- BOUNDS STILL OUTRANKS RESIDENCY.
// Sail raises RESIDENCY_FAULT only for an access that would OTHERWISE have
// succeeded. In the RTL, bounds was never an explicit test -- it was the
// fall-through default of every cause chain -- so making residency the new
// default required promoting bounds to a real arm in all seven. Get that
// backwards and an out-of-bounds access reports 0x0A, which invites a
// pager to fetch an object to service a request that will be refused on
// arrival. An attacker with a paged-out object and a wild offset could
// then drive unbounded paging. This part uses an offset far outside
// Length, so the correct design reports 0x01 and the inverted one 0x0A.
//
// PART C -- the check is on ALL SEVEN dereference families, not just OCL.
// The RTL collapses Sail's two checkers into one shared lookup feeding
// seven violation expressions and seven cause chains. Missing any single
// one leaves that family silently dereferencing a paged-out object while
// the other six pass their tests. Store, capability-load and NMC are
// exercised here alongside the plain load.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                            // trap counter

    // ═══ PART A: OCL.D through a paged-out object -> 0x0A ═══
    li   x2, 0
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x11, x2  // ocl.d c11, x2, x10
    li   t1, 1
    bne  x20, t1, fail
    li   t1, 0x16A                         // (cap_idx 11 << 5) | cause 0x0A
    bne  x25, t1, fail
    li   x21, 0x600D

    // OCS.D -- the store family, same object
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x11, x2   // ocs.d c11, x2, x3
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x22, 0x600D

    // ═══ PART B: out of bounds AND non-resident -> 0x01, NOT 0x0A ═══
    // Offset 0x200 is far outside Length 0x40.
    li   x2, 0x200
    .insn r 0x0b, 0x3, 0x00, x10, x11, x2  // ocl.d c11, x2, x10
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0x161                         // (cap_idx 11 << 5) | cause 0x01
    bne  x25, t1, fail
    li   x23, 0x600D

    // ═══ PART C: ALL SEVEN DEREFERENCE FAMILIES ═══
    // Written this exhaustively because mutation testing proved it was
    // necessary: with only OCL.D, OCS.D and OCL.C covered, the residency
    // term could be deleted from OCS.C, NMC.W, NMC.D or Atomic and all 67
    // tests still passed. Sail expresses this check once; the RTL collapses
    // Sail's two checkers into one shared lookup that feeds SEVEN violation
    // expressions, so "the check exists" has to be established seven times.
    // c11 carries Permit_NMC_Compute precisely so the NMC and Atomic
    // families reach residency instead of stopping at a permission cause.

    // NMC_ADD.D -- its own bounds signal ($veda_nmc_bounds_ok_d)
    li   x2, 0
    li   x4, 1
    .insn r 0x0b, 0x3, 0x02, x4, x11, x2   // veda.nmc.add.d c11, x2, x4
    li   t1, 4
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x24, 0x600D

    // NMC_ADD.W -- a DIFFERENT bounds signal ($veda_nmc_bounds_ok_w), and
    // therefore a genuinely separate cause chain, not a duplicate of .D
    .insn r 0x0b, 0x2, 0x02, x4, x11, x2   // veda.nmc.add.w c11, x2, x4
    li   t1, 5
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x28, 0x600D

    // OCL.C -- the capability-load family, its own bounds signal and its
    // own RTL-only 0x08 misalignment arm ahead of residency.
    .insn r 0x0b, 0x4, 0x00, x5, x11, x2   // ocl.c c5, c11, x2
    li   t1, 6
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x26, 0x600D

    // OCS.C -- the capability-store family
    .insn r 0x0b, 0x4, 0x01, x5, x11, x2   // ocs.c c11, x2, c5
    li   t1, 7
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x29, 0x600D

    // Veda-Atomic -- routes through the load/store checker but takes its
    // bounds from the doubleword signal, so it is a seventh distinct chain
    li   x9, 5
    .insn r 0x2b, 0x3, 0x00, x10, x11, x9  // veda.atomic.add x10, c11, x9
    li   t1, 8
    bne  x20, t1, fail
    li   t1, 0x16A
    bne  x25, t1, fail
    li   x17, 0x600D

    // ═══ PART D: bounds outranks residency ON THE NMC CHAIN TOO ═══
    // PART B proved it for $veda_bounds_ok. The NMC families use different
    // bounds signals, and each cause chain had to be paired with its own --
    // pairing the wrong one compiles clean, so each ordering is checked
    // where it can actually be observed.
    //
    // NMC BOUNDS COMES FROM THE CAPABILITY'S OWN Offset FIELD, not from a
    // GPR. This cost a debugging cycle worth recording: the rs2 operand of
    // veda.nmc.add is the ADDEND, not an offset, so passing a large rs2
    // does not put the access out of bounds -- it just adds a large number.
    // The access stayed in bounds and correctly reported 0x0A, and the test
    // was asserting something the instruction cannot do.
    //
    // OCA moves the offset instead. 0x3C is INSIDE Length 0x40, so OCA
    // accepts it, but an 8-byte access from there needs 0x44 and a 4-byte
    // one needs 0x40 -- both out of bounds. OCA works on a paged-out object
    // by design: it is manipulate-family, and manipulation never
    // dereferences, which is the same split that lets a holder keep and
    // narrow a capability while its object is away.
    // Offset 0x3C is chosen to SPLIT the two NMC widths, which turns this
    // into a stronger claim than "bounds outranks residency": it proves
    // .W and .D consult DIFFERENT bounds signals. From 0x3C a doubleword
    // needs 0x44 (out of bounds, Length is 0x40) but a word needs exactly
    // 0x40 (in bounds). So the same capability, at the same offset, must
    // produce 0x01 for .D and 0x0A for .W. A design that wired both chains
    // to one bounds signal cannot produce both answers.
    //
    // (The first version of this used 0x3C for both and expected 0x01
    // twice. The word case is exactly at the boundary and passes -- the
    // off-by-one was in the test, not the RTL. Kept as the discriminator
    // it accidentally turned out to be.)
    li   x9, 0x3C
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x9  // oca c11, c11, x9 -> Offset=0x3C
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x4, x11, x2   // nmc.add.d -- needs 0x3C+8 = 0x44
    li   t1, 9
    bne  x20, t1, fail
    li   t1, 0x161                         // cause 0x01 (bounds), NOT 0x0A
    bne  x25, t1, fail
    .insn r 0x0b, 0x2, 0x02, x4, x11, x2   // nmc.add.w -- needs 0x3C+4 = 0x40
    li   t1, 10
    bne  x20, t1, fail
    li   t1, 0x16A                         // IN bounds, so residency: 0x0A
    bne  x25, t1, fail
    li   x18, 0x600D

    // And now push the word case out too, so the .W chain's own bounds arm
    // is exercised rather than only its residency default.
    li   x9, 2
    .insn r 0x5b, 0x1, 0x0a, x11, x11, x9  // oca c11, c11, x9 -> Offset=0x3E
    .insn r 0x0b, 0x2, 0x02, x4, x11, x2   // nmc.add.w -- needs 0x3E+4 = 0x42
    li   t1, 11
    bne  x20, t1, fail
    li   t1, 0x161                         // cause 0x01 (bounds)
    bne  x25, t1, fail
    li   x19, 0x600D

    // ═══ CONTROL: a RESIDENT object still dereferences normally ═══
    // Without this, a design that faulted on every dereference would pass
    // everything above.
    li   x1, 1
    .insn i 0x0b, 0x5, x6, x1, 0           // veda.bind c6, x1
    li   x7, 0xABCD
    .insn r 0x0b, 0x3, 0x01, x7, x6, x2    // ocs.d c6, x2, x7
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x8, x6, x2    // ocl.d c6, x2, x8
    li   t1, 11
    bne  x20, t1, fail                     // no new trap
    li   t1, 0xABCD
    bne  x8, t1, fail                      // and the data round-tripped
    li   x27, 0x600D

    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x24, t1, fail
    bne  x26, t1, fail
    bne  x27, t1, fail
    bne  x28, t1, fail
    bne  x29, t1, fail
    bne  x17, t1, fail
    bne  x18, t1, fail
    bne  x19, t1, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    // Scratch is x12/x13, NOT t5/t6. In the RISC-V ABI t5 is x30 and t6 is
    // x31 -- both used as result registers here, so the handler was
    // overwriting its own test's sentinels. That is the fourth time this
    // exact clash has appeared in this project; the fix is to name the raw
    // x-registers in handlers rather than ABI aliases, so the collision is
    // visible at the point of use instead of one ABI table away.
    csrr x12, mcause
    li   x13, 0x18
    bne  x12, x13, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr x12, mepc
    addi x12, x12, 4
    csrw mepc, x12
    mret
fail:
    li   x30, 0xBAD
done:
    j    done
