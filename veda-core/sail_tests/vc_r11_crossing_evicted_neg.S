.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R11 (DESIGN_07 Tier H) -- A DOMAIN CROSSING MUST REVALIDATE ITS CODE
# OBJECT.
#
# THE GAP THIS TEST EXISTS FOR. DESIGN_02 Phase 2 added object residency to
# Bind and to all six data-dereference families. It was never added to the
# three crossings, which are the only other consumers of an object's Base.
# So a sealed CODE capability survived an eviction that a DATA capability to
# the very same object did not: page the object out, then Bind it (correctly
# refused, 0x0A) versus OCInvoke through a code capability naming it -- and
# the jump was taken. Reproduced on the model before this fix.
#
# It is not a paging bug. PART B below shows ODT-Destroy never revoked the
# execute view either, which falsifies this project's own stated reason for
# CAndPerm existing: "so a later ODT-Destroy still revokes every view."
# Paging only made the state reachable on a routine path.
#
# PART A -- OCInvoke through a PAGED-OUT code object traps TAG (0x02).
#
#   The cause is worth dwelling on, because the first version of this test
#   asserted RESIDENCY (0x0A) and was WRONG -- the model was right. Page-out
#   BUMPS the generation, so any capability held across it fails the
#   generation check before residency is ever consulted. That is not a
#   defect, it is the DESIGN_02 Option-A contract working exactly as chosen:
#   the CAPABILITY really is permanently dead, because its generation is
#   gone forever. The OBJECT is still serviceable, and the way software
#   learns that is by re-Binding, which reports 0x0A.
#
#   So the division of labour is: a held capability gets the permanent
#   verdict (0x02, re-Bind), and a fresh Bind gets the serviceable one
#   (0x0A, page it in). Both are correct; they answer different questions.
#
# PART B -- OCInvoke through a DESTROYED code object also traps 0x02, but by
#           the other half of the same check: the entry is no longer valid.
# PART C -- OCJALR gets the identical check. It is intra-domain by design and
#           so carries no region check, but intra-domain says which table
#           resolves the Object_ID, not whether the object still exists.
# PART D -- THE POSITIVE CONTROL. A crossing into a live, resident object
#           still works. Without it, a model that trapped on every crossing
#           would pass everything above.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                          # trap counter

    # ---- Object_ID 700: CODE. Base=landing_pad, Length unbounded (so the
    #      landing pad's own tohost store is not blocked), Perms =
    #      Permit_Execute(1) | Permit_Invoke(10) = 0x0402
    li   t1, 0xFFFFFFFFFF
    slli t1, t1, 16
    ori  t1, t1, 0x0402
    csrw 0x7C4, t1
    la   t2, landing_pad
    li   x1, 700
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # ---- Object_ID 703: a SECOND code object, for the PART D control
    la   t2, control_pad
    li   x1, 703
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # ---- Object_ID 701: DATA (Permit_Invoke, non-executable)
    li   x1, 701
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate

    # ---- Object_ID 702: type authority (Permit_Seal | Permit_Unseal)
    li   x1, 702
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate

    li   x1, 700
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1   -- CODE 700
    li   x1, 703
    .insn i 0x0b, 0x5, x6, x1, 0         # veda.bind c6, x1   -- CODE 703
    li   x1, 701
    .insn i 0x0b, 0x5, x1, x1, 0         # veda.bind c1, x1   -- DATA
    li   x1, 702
    .insn i 0x0b, 0x5, x2, x1, 0         # veda.bind c2, x1   -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- sealed CODE 700
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2   -- sealed DATA
    .insn r 0x5b, 0x1, 0x10, x7, x6, x2  # cseal c7, c6, c2   -- sealed CODE 703

    # ═══ PART A: page out 700, then cross through c3 ═══
    li   x1, 700
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0  # veda.odt.page.out

    # the capability's tag is untouched -- this design checks at USE
    .insn r 0x5b, 0x0, 0x03, x10, x3, x0 # cgettag x10, c3
    li   t1, 1
    bne  x10, t1, fail                   # fixture sanity

pa_site:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- must TRAP 0x02
    li   t1, 1
    bne  x20, t1, fail                   # exactly one trap
    li   t1, 0x62                        # (cap_idx 3 << 5) | cause 0x02
    bne  x25, t1, fail
    la   t1, pa_site
    bne  x26, t1, fail                   # mepc is the crossing, resumable
    li   x21, 0x600D

    # ═══ PART B: destroy 703, then cross through c7 -- TAG (0x02) ═══
    # Distinct from PART A on purpose: destroyed is permanent, paged-out is
    # serviceable, and reporting one for the other misdirects the handler.
    li   x1, 703
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0  # veda.odt.destroy

pb_site:
    .insn r 0x5b, 0x1, 0x12, x0, x7, x4  # ocinvoke c7, c4 -- must TRAP 0x02
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0xE2                        # (cap_idx 7 << 5) | cause 0x02
    bne  x25, t1, fail
    li   x22, 0x600D

    # ═══ PART C: OCJALR through the paged-out 700 ═══
    # c3 is sealed with c2's otype; OCJALR unseals via the type authority.
pc_site:
    .insn r 0x5b, 0x1, 0x14, x0, x3, x2  # ocjalr c3, c2 -- must TRAP 0x02
    li   t1, 3
    bne  x20, t1, fail
    li   t1, 0x62
    bne  x25, t1, fail
    li   x23, 0x600D

    # ═══ PART D: THE POSITIVE CONTROL ═══
    # Page 700 back in, re-Bind (the old capability is stale by generation,
    # which is the cached-Base contract working as designed), re-seal, and
    # cross. This must SUCCEED and land.
    la   t2, landing_pad
    li   x1, 700
    .insn r 0x0b, 0x0, 0x05, x5, x1, t2  # veda.odt.page.in
    li   t1, 3
    bne  x20, t1, fail                   # page-in itself must not trap

    li   x1, 700
    .insn i 0x0b, 0x5, x8, x1, 0         # veda.bind c8, x1 -- fresh generation
    .insn r 0x5b, 0x1, 0x10, x9, x8, x2  # cseal c9, c8, c2
    li   x24, 0x600D
    .insn r 0x5b, 0x1, 0x12, x0, x9, x4  # ocinvoke c9, c4 -- must SUCCEED

    j    fail                            # fell through without jumping

.balign 4
landing_pad:
    # Reached only via PART D's crossing into a live, resident object.
    li   t1, 3
    bne  x20, t1, fail                   # still exactly three traps
    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    bne  x24, t1, fail
    RVMODEL_HALT_PASS

.balign 4
control_pad:
    j    fail                            # 703 is destroyed; never reached

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail                    # every fault here is a Veda trap
    csrr x25, mtval
    csrr x26, mepc
    addi x20, x20, 1
    addi x26, x26, 4
    csrw mepc, x26
    addi x26, x26, -4                    # keep the faulting PC for assertion
    mret

fail:
    RVMODEL_HALT_FAIL
