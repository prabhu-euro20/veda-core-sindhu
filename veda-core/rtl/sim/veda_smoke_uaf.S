.section .text
.global _start
// TEMPORAL SAFETY -- use-after-free, on every dereference path.
//
// The mutation census (difftest/MUTATION_CENSUS_DEREF.md) removed
// $veda_gen_stale from each of the seven dereference violation expressions and
// found it SURVIVES ON SIX OF SEVEN. That term is the entire use-after-free
// defence: an object's generation is bumped by Destroy and by page-out, and
// this is the term that refuses a capability whose generation no longer
// matches. Delete it and a stale capability reads and writes freed memory with
// no trap -- and every one of the 82 tests stayed green.
//
// THE CONSTRUCTION, and it is the point of the test.
// $veda_gen_stale is (!valid) || (odt_gen != cap_gen), so simply destroying an
// object proves only the FIRST half: the entry goes invalid and any check of
// validity would also catch it. The half that matters for temporal safety is
// the second: the object is freed, the slot is REUSED, the entry is valid
// again, and an old capability must not reach the new occupant.
//
// So each phase does destroy THEN RE-POPULATE. Afterwards the stale capability
// is tagged, unsealed, permitted, in bounds and resident -- every other check
// passes -- and ONLY the generation differs. Nothing but $veda_gen_stale can
// refuse it. That is what makes this a single-term discriminator rather than a
// test that happens to trap.
//
// Object 20 is minted fresh rather than reusing a seeded one, so nothing here
// depends on reset fixtures -- which the difftest has shown the two layers do
// not agree on (16 of 16 capability registers diverge at reset).
//
// Six phases, one per chain the census found unverified:
//   P1 ocs   P2 ocl   P3 ocsc   P4 oclc   P5 nmc_add_d   P6 nmc_add_w
//
// mtval is {cap_idx:5, cause:5}; every phase expects cause 0x02 on c1, so 0x22.
//
// Register discipline: explicit x-names only. This corpus has been bitten five
// times by ABI-named scratch clobbering a result.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // Base=0x80010200, Length=0x40, Perms=0x100C (Load|Store|NMC_Compute)
    li   x1, 20
    li   x2, 0x800102000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate 20

    li   x1, 20
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 20   -- the capability that will go stale

    // free it, then hand the SAME SLOT back out. c1 now names a live, valid,
    // resident object of the right length and perms -- and a dead generation.
    li   x1, 20
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0   # veda.odt.destroy 20   (bumps generation)
    li   x1, 20
    li   x2, 0x800102000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate 20  (slot reused)

    // ---------------- P1: ocs.d ----------------
    li   x2, 0
    li   x3, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2   # ocs.d through the stale c1
    mv   x10, x22

    // ---------------- P2: ocl.d ----------------
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x4, x1, x2   # ocl.d through the stale c1
    mv   x11, x22

    // ---------------- P3: ocs.c ----------------
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x1, x2   # ocs.c through the stale c1
    mv   x12, x22

    // ---------------- P4: ocl.c ----------------
    li   x2, 0
    .insn r 0x0b, 0x4, 0x00, x6, x1, x2   # ocl.c through the stale c1
    mv   x13, x22

    // ---------------- P5: nmc_add.d ----------------
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x7, x1, x2   # nmc_add.d through the stale c1
    mv   x14, x22

    // ---------------- P6: nmc_add.w ----------------
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x1, x2   # nmc_add.w through the stale c1
    mv   x15, x22

    // ---------------- CONTROL ----------------
    // A FRESH bind to the very same object must work. Without this the six
    // phases above would also pass if the object were simply broken, or if
    // every dereference through c1 trapped for some unrelated reason.
    li   x1, 20
    .insn i 0x0b, 0x5, x8, x1, 0          # veda.bind c8, 20  (current generation)
    li   x2, 0
    li   x3, 0x600D
    .insn r 0x0b, 0x3, 0x01, x3, x8, x2   # ocs.d -- must SUCCEED
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x16, x8, x2  # ocl.d -- must read 0x600D back
    mv   x17, x20                          # trap count must still be 6

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x21, mcause
    csrr x22, mtval
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
