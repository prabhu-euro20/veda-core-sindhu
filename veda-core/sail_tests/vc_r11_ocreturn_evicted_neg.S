.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R11 (DESIGN_07 Tier H) -- OCRETURN MUST REVALIDATE ITS CODE OBJECT TOO.
#
# WHY THIS FILE EXISTS. vc_r11_crossing_evicted_neg covers OCInvoke and
# OCJALR. Mutation testing then showed OCRETURN's revalidation could be
# deleted with all 85 tests still passing -- the fix was in place on all
# three crossings, but only two of them were being measured. A check that
# no test can distinguish from its own absence is not verified, however
# correct it happens to be.
#
# OCRETURN is the crossing where an evicted object is MOST likely in
# practice, not least: a callee runs for an unbounded amount of time, and
# the caller's code object is exactly the kind of cold, idle page a demand
# pager picks as a victim. A return into a since-evicted caller lands on a
# stale Base, and unlike the region case there is nothing downstream to
# catch it -- instruction fetch never revalidates.
#
# PART A -- return through a sentry whose object was PAGED OUT traps 0x02.
#           Page-out bumps the generation, so the sentry fails the
#           generation half of the check. (The residency half is
#           unreachable via page-out for exactly this reason -- see the
#           note in vc_r11_crossing_evicted_neg.)
# PART B -- return through a sentry whose object was DESTROYED traps 0x02
#           by the other half: the entry is no longer valid.
# PART C -- the positive control. A return into a live, resident object
#           still lands. Without it, a model that trapped on every return
#           would pass both parts above.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                          # trap counter

    # veda_attr: Length UNBOUNDED, Perms = Permit_Execute(1)|Permit_Invoke(10)
    # Unbounded so that OCRETURN's PCC narrowing still leaves the landing
    # pad able to reach the HTIF tohost word.
    li   t1, 0xFFFFFFFFFF
    slli t1, t1, 16
    ori  t1, t1, 0x0402
    csrw 0x7C4, t1

    # Object_ID 710 -- the caller's code object, PART A's victim
    la   t2, ret_pad_a
    li   x1, 710
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # Object_ID 711 -- PART B's victim
    la   t2, ret_pad_b
    li   x1, 711
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # Object_ID 712 -- PART C's live control
    la   t2, ret_pad_c
    li   x1, 712
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # Mint three real sentries. csealentry is the only producer of
    # VEDA_OTYPE_SENTRY, which is what makes a sentry self-authenticating
    # and lets OCRETURN take one operand instead of two.
    li   x1, 710
    .insn i 0x0b, 0x5, x1, x1, 0         # veda.bind c1, x1
    .insn r 0x5b, 0x1, 0x15, x2, x1, x0  # csealentry c2, c1  -- sentry A
    li   x1, 711
    .insn i 0x0b, 0x5, x3, x1, 0         # veda.bind c3, x1
    .insn r 0x5b, 0x1, 0x15, x4, x3, x0  # csealentry c4, c3  -- sentry B
    li   x1, 712
    .insn i 0x0b, 0x5, x6, x1, 0         # veda.bind c6, x1
    .insn r 0x5b, 0x1, 0x15, x7, x6, x0  # csealentry c7, c6  -- sentry C

    # ═══ PART A: page out the caller's object, then return into it ═══
    li   x1, 710
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0  # veda.odt.page.out

    # the sentry's tag is untouched -- this design checks at USE, not at
    # eviction, which is precisely why the check has to exist at the use
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0 # cgettag x10, c2
    li   t1, 1
    bne  x10, t1, fail                   # fixture sanity

pa_site:
    .insn r 0x5b, 0x1, 0x16, x0, x2, x0  # ocreturn c2 -- must TRAP 0x02
    li   t1, 1
    bne  x20, t1, fail                   # exactly one trap
    li   t1, 0x42                        # (cap_idx 2 << 5) | cause 0x02
    bne  x25, t1, fail
    la   t1, pa_site
    bne  x26, t1, fail                   # mepc is the return, resumable
    li   x21, 0x600D

    # ═══ PART B: destroy the object, then return into it ═══
    li   x1, 711
    .insn r 0x0b, 0x1, 0x03, x5, x1, x0  # veda.odt.destroy

pb_site:
    .insn r 0x5b, 0x1, 0x16, x0, x4, x0  # ocreturn c4 -- must TRAP 0x02
    li   t1, 2
    bne  x20, t1, fail
    li   t1, 0x82                        # (cap_idx 4 << 5) | cause 0x02
    bne  x25, t1, fail
    li   x22, 0x600D

    # ═══ PART C: the positive control -- a live object still returns ═══
    li   x23, 0x600D
    .insn r 0x5b, 0x1, 0x16, x0, x7, x0  # ocreturn c7 -- must SUCCEED

    j    fail                            # fell through without jumping

.balign 4
ret_pad_a:
    j    fail                            # 710 is paged out; never reached
.balign 4
ret_pad_b:
    j    fail                            # 711 is destroyed; never reached
.balign 4
ret_pad_c:
    # Reached only via PART C's return into a live, resident object.
    li   t1, 2
    bne  x20, t1, fail                   # still exactly two traps
    li   t1, 0x600D
    bne  x21, t1, fail
    bne  x22, t1, fail
    bne  x23, t1, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail                    # every fault here is a Veda trap
    csrr x25, mtval
    csrr x26, mepc
    addi x20, x20, 1
    addi t3, x26, 4
    csrw mepc, t3
    mret

fail:
    RVMODEL_HALT_FAIL
