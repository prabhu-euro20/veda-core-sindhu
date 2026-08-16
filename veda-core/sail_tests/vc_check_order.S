.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R19 increment 1 -- the ORDER of the dereference check chain.
#
# A 0x0C copy-on-write fault is not a refusal, it is a REPAIR REQUEST: it tells
# a handler to allocate, copy, and hand back a fresh writable object. Raising it
# for an access that was going to be refused anyway arms that work for nothing.
# This file's own residency arm already states the rule -- a repair fault is
# raised "only for an access that would otherwise have SUCCEEDED" -- and the cow
# arm violated it from the day it landed.
#
# The whole corpus was blind to this: no existing test makes an access fail MORE
# THAN ONE check at once, so nothing could see which cause won. That is exactly
# why the ordering defect survived. These three phases are the first.
#
# PHASE A is the one genuine security closure, and it is not the one first
# claimed. veda_setbounds with rs2 = 0 computes window_ok = Offset + 0 <= Length,
# trivially true, so a tagged, unsealed, generation-current capability of
# Length 0 is constructible in ONE instruction. Under the OLD order that
# zero-entitlement capability stored, reached the cow arm before bounds was ever
# consulted, took 0x0C, and a handler would have rebound it to a FULL-Length
# capability minted from the ENTRY. Under the new order every offset is out of
# bounds, so it can never arm a split.
#   old order -> 0x0C   new order -> 0x01 BOUNDS
#
# PHASE B: you cannot copy an object that is not in memory. If 0x0C fires on a
# non-resident object the handler dereferences a Base whose frame the pager may
# already have reassigned -- the stale-Base hazard DESIGN_02 records for paging.
# Residency must be repaired first; the retry then raises 0x0C.
#   old order -> 0x0C   new order -> 0x0A RESIDENCY
#
# PHASE C is the control, and without it A and B would also pass if the cow arm
# had simply been deleted. An in-bounds, resident store to a cow object must
# STILL report 0x0C, in both orders.
#
# mtval is {cap_idx:5, cause:5}, so the expected values are cap<<5 | cause.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x10, 0
    li   x11, 0
    li   x12, 0
    li   x13, 0

    # ---------------- PHASE A ----------------
    # Bind BEFORE set.cow deliberately, so c1 RETAINS store permission. That
    # isolates this phase to the bounds-versus-cow ordering alone -- the gated
    # permission arm is not involved, and cannot be credited for the result.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 1
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1

    li   x2, 0
    .insn r 0x5b, 0x1, 0x08, x2, x1, x2   # csetbounds c2, c1, x2=0  -> Length 0

    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x2, x2   # ocs.d through c2, offset 0
    mv   x10, x25                          # want (2<<5)|0x01 = 0x41

    # ---------------- PHASE B ----------------
    # c12 names Object_ID 600: seeded valid, generation 0, resident = FALSE.
    # It is the only way to reach the dereference-side residency arm.
    li   x1, 600
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 600 <- 1

    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x12, x2  # ocs.d through c12, offset 0
    mv   x11, x25                          # want (12<<5)|0x0A = 0x18A

    # ---------------- PHASE C (control) ----------------
    # In bounds, resident, cow. Must STILL be 0x0C, or the arm is simply gone.
    li   x2, 0
    li   x3, 0xA5
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2   # ocs.d through c1, offset 0
    mv   x12, x25                          # want (1<<5)|0x0C = 0x2C

    # ---------------- PHASE D (the gate) ----------------
    # Bind AFTER set.cow, so veda_bind_perms masks with 0xFFF7 and c3 lacks
    # PERM_STORE by construction. Storing through it must still report 0x0C
    # "copy me", never 0x13 "you may not write" -- that is the whole job of the
    # not(entry.cow) conjunct on the permission arm, and it is what keeps
    # copy-on-write reachable once the cow arm moved to the bottom of the chain.
    #
    # THIS PHASE EXISTS BECAUSE THE MUTANT SURVIVED. Removing the gate was
    # caught by NOTHING in a 94-test corpus: the existing cow tests inspect the
    # attenuated capability with CGetPerm and never DEREFERENCE through it --
    # attenuation tested as bookkeeping, never as enforcement, the identical
    # shape as the CAndPerm defect. Predicting the mutant is what found it.
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1  (still cow)
    li   x1, 1
    .insn i 0x0b, 0x5, x3, x1, 0          # veda.bind c3, 1  -> store STRIPPED
    li   x2, 0
    li   x6, 0xA5
    .insn r 0x0b, 0x3, 0x01, x6, x3, x2   # ocs.d through c3, offset 0
    mv   x13, x25                          # want (3<<5)|0x0C = 0x6C

    # leave the two objects un-cowed so nothing downstream inherits the policy
    li   x1, 1
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4
    li   x1, 600
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4

    li   t1, 4
    bne  x20, t1, fail                     # exactly four traps, no more, no fewer
    li   t1, 0x41
    bne  x10, t1, fail
    li   t1, 0x18A
    bne  x11, t1, fail
    li   t1, 0x2C
    bne  x12, t1, fail
    li   t1, 0x6C
    bne  x13, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
