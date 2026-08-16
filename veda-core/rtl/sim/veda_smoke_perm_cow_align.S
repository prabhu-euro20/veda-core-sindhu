.section .text
.global _start
// The last seven census survivors. Three different mechanisms, and each one has
// to be ISOLATED -- if two can fire on the same access, the mutant for one
// survives because the other silently does its work. That is exactly what
// happened to veda_smoke_check_order.S, where copy-on-write was firing the trap
// that the bounds phases were credited for.
//
// P1-P3  !$veda_perm_load_ok on oclc, nmc_add.w, nmc_add.d.
//        c5 = CAndPerm(c1, 0xFFFB) strips PERM_LOAD (bit 2) and keeps store and
//        NMC_Compute, on a NON-cow object. NMC needs LOAD as well as store and
//        NMC_Compute -- that was R15's finding, that a value reaching software
//        from memory is a load whatever single instruction performs it.
// P4     $veda_capmem_misaligned on oclc. Offset 8 is in bounds and the
//        capability is otherwise perfect; only the 32-byte capability-granule
//        rule refuses it.
// P5-P7  $veda_cow_write on ocsc, nmc_add.w, atomic. Object 21 is cow and c6
//        was bound BEFORE set.cow, so it still carries store -- meaning the
//        permission arm cannot fire and only the cow term can.
//
// Objects minted fresh, not seeded: all 16 capability registers diverge between
// the layers at reset.
//
// mtval = {cap_idx:5, cause:5}.
//   P1-P3 c5 | 0x12 = 0xB2     P4 c1 | 0x08 = 0x28     P5-P7 c6 | 0x0C = 0xCC
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // object 20 -- NOT cow. Base 32-byte aligned, Perms Load|Store|NMC.
    li   x1, 20
    li   x2, 0x800102000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 20
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 20

    li   x4, 0xFFFB                        # clear bit 2 = PERM_LOAD
    .insn r 0x5b, 0x1, 0x17, x5, x1, x4   # candperm c5, c1, 0xFFFB  (funct3=001, NOT 000)

    // ---------------- P1-P3: no load permission ----------------
    li   x2, 0
    .insn r 0x0b, 0x4, 0x00, x7, x5, x2   # ocl.c through c5
    mv   x10, x22
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x5, x2   # nmc_add.w through c5
    mv   x11, x22
    li   x2, 0
    .insn r 0x0b, 0x3, 0x02, x7, x5, x2   # nmc_add.d through c5
    mv   x12, x22

    // ---------------- P4: misaligned capability load ----------------
    li   x2, 8                             # in bounds (8+32 <= 64), NOT 32-aligned
    .insn r 0x0b, 0x4, 0x00, x7, x1, x2   # ocl.c through c1
    mv   x13, x22

    // ---------------- P5-P7: copy-on-write is the ONLY term that can fire ----------------
    li   x1, 21
    li   x2, 0x800102800040100C            # a second object, Base 0x80010280
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 21
    .insn i 0x0b, 0x5, x6, x1, 0          # veda.bind c6, 21  -- BEFORE cow, so it keeps store
    li   x1, 21
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 21 <- 1

    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x6, x6, x2   # ocs.c through c6
    mv   x14, x22
    li   x2, 0
    .insn r 0x0b, 0x2, 0x02, x7, x6, x2   # nmc_add.w through c6
    mv   x15, x22
    li   x2, 0
    .insn r 0x2b, 0x3, 0x00, x7, x6, x2   # veda.amoadd.d through c6
    mv   x16, x22

    // ---------------- CONTROL ----------------
    // c1 is unattenuated, aligned, in bounds, on a non-cow object: it must work.
    li   x2, 0
    li   x3, 0x600D
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2   # ocs.d
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x17, x1, x2  # ocl.d -- must read 0x600D back
    mv   x18, x20                          # trap count must still be 7

    li   x1, 21
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # leave object 21 un-cowed

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x22, mtval
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
