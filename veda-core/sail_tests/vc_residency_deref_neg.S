.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 (Phase 2, increment 1) -- THE DEREFERENCE GATE, which is the term
# that closes the actual security hole.
#
# The other two residency tests bind a non-resident object, so Bind faults
# FIRST and neither ever reaches a dereference. That means the bind gate is
# well covered and the dereference gate is not covered at all -- and the
# dereference gate is the one that matters, because it is what stops a
# capability minted while the object was resident, held across a page-out,
# from reading whatever now occupies that memory.
#
# THE HAZARD, precisely. The access path computes its address from
# `cap.Base`, the capability's CACHED copy -- never from the live entry.
# A page-out leaves `valid` true (the object still exists) and does not bump
# `generation` (only Populate and Destroy do). So without the residency term,
# every existing check passes and the load lands in reused memory.
#
# Reaching that state needs a capability that ALREADY names a non-resident
# object. No instruction sequence can build one -- Bind is residency-gated,
# and Populate is precisely what establishes residency -- so c12 is
# reset-seeded to name Object_ID 600 (seeded valid, generation 0, but
# resident = false). That is the same direct state-injection technique the
# region-2 capability fixtures already use, and it models exactly the legal
# state of a capability held across an eviction.
#
# The seeded capability is deliberately well-formed in EVERY other respect --
# tagged, unsealed, generation-matched, Load|Store permitted, and the access
# is in bounds -- so it passes all five earlier checks and the FIRST and ONLY
# thing that can stop it is residency. That isolation is the point: a fault
# for any other reason would prove nothing about this gate.
#
# Expected mtval = cap_idx << 5 | cause = (12 << 5) | 0x0A = 0x18A.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # Precondition: the seeded capability really is well-formed, so a failure
    # below is about the residency gate and not about a broken fixture.
    .insn r 0x5b, 0x0, 0x03, x5, x12, x0   # cgettag  x5,  c12 -- expect 1
    li   t1, 1
    bne  x5, t1, fail
    .insn r 0x5b, 0x0, 0x04, x6, x12, x0   # cgettype x6,  c12 -- expect 0xFFFF (unsealed)
    li   t1, 0xFFFF
    bne  x6, t1, fail

    li   x3, 0
deref_instr:
    .insn r 0x0b, 0x3, 0x00, x7, x12, x3   # ocl.d x7, c12, x3 -- must RESIDENCY_FAULT

    RVMODEL_HALT_FAIL              # reached only if the load wrongly succeeded

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x18A                 # (12 << 5) | 0x0A
    bne  t3, t4, fail

    # RESUMABLE: mepc must point at the faulting load itself, so a pager can
    # fetch the object and re-execute.
    csrr t3, mepc
    la   t4, deref_instr
    bne  t3, t4, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
