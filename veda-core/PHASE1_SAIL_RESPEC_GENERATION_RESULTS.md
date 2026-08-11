# Phase 1 (Sail respec) -- Increment 4: widen the generation counter, retire the 255-reuse wall

**Date:** 2026-08-11. **Layer:** Sail formal model. **Repos:** model in `Veda-Core-sail-riscv`
branch `phase1-respec`; tests + this doc in `veda-core-sindhu`. **Design authority:**
`veda-core-linux` `design/DESIGN_01_CAPABILITY_FORMAT_RESPEC.md`.

## What changed

`odt_entry.generation` widened **8 -> 24 bits**, matching the capability's own 24-bit generation
field. This removes the last narrow-to-wide bridge (the recheck and Bind no longer zero-extend
an 8-bit entry field into the 24-bit capability field -- they compare and copy directly), and it
removes the **fifth wall**: the retirement ceiling.

A slot could previously be destroyed/re-populated only **255 times** before permanent
retirement. That ceiling was not arbitrary -- an 8-bit counter that simply wrapped would revive
a stale capability whose cached generation matched the wrapped value (a real use-after-free,
reproduced on RTL in Milestone 16), so retirement-at-saturation was the correct fix, but it
burned a slot forever after 255 reuses. Under Linux-scale churn that is a genuine liveness
limit. At 24 bits the ceiling is **~16.7M reuse cycles** per slot.

The retirement mechanism itself is unchanged in kind: on destroy or re-populate, the counter
increments; once it reaches the maximum it freezes there, and the next bump retires the slot
(`retired = true`, all future populates refused). Only the width, and hence the threshold
constant (`0xff` -> `0xffffff`), changed.

## The real problem this increment had to solve: testing a threshold too large to loop to

The original negative test reached the 8-bit threshold with `.rept 256` -- destroy the slot 256
times, watch it retire. At 24 bits that becomes `.rept 16777216`, which is not a test: it will
not assemble and run in any reasonable time, and even if it did it would prove nothing a
smaller check does not.

**Decision: direct ODT-state injection near the boundary, not a loop and not a reduced
threshold.** This is the project's own established pattern -- `veda_test_seed_odt()` already
seeds every test object by writing ODT state directly at reset (none is created by a real
ODT-Populate instruction), and the RTL uses the identical technique for the owner-hart tests it
has no second hart to drive. A new seed, **Object_ID=55, generation = 0xFFFFFE** (one below the
real threshold), lets the test drive the genuine boundary with two destroys:

- Destroy #1: `0xFFFFFE -> 0xFFFFFF` (saturated, not yet retired)
- Destroy #2: counter already at max -> slot retired

This is deliberately **not** a reduced-threshold stand-in (e.g. a config knob lowering the
ceiling to 256). It exercises the **true 24-bit threshold arithmetic** -- the actual
`== 0xffffff` freeze test and the actual retire-on-next-bump -- at the width that ships. A
reduced threshold would leave the real boundary constant untested.

## Verification

| Stage | Result |
|---|---|
| Baseline before increment (increment-3 model) | 70/70 |
| Increment 4, full corpus | **70/70** |

The positive test `vc_gen_retire.S` was **unaffected**: it only does 5 re-populates (far under
any threshold) to prove a normal slot keeps working, which is as true at 24 bits as at 8. Only
the negative test needed rework, and it was rewritten to the seed-and-two-destroys form above
with its asserted properties **unchanged**: the post-retirement re-populate is still refused
(Illegal_Instruction, mcause=2 at the re-populate PC), and the stale capability still hard-traps
(Tag Violation, cause 0x02).

### Mutation testing

To prove the new test genuinely exercises the threshold rather than passing vacuously:

- **Mutant -- move the seed away from the boundary** (`generation = 0xFFFFFE` -> `0x000010`).
  Two destroys then leave the counter far below the threshold, the slot is never retired, and
  the re-populate succeeds instead of being refused. **Result: 69/70 -- only
  `vc_gen_retire_neg` failed.** That is the sharpest available check of the seed-injection
  strategy: the test genuinely depends on the slot reaching retirement (it is not passing
  because of some incidental property of the seeded object), and the mutation was precise --
  it did not disturb the other 69 tests. Together with the corpus staying green on the real
  seed, this establishes that the near-boundary injection exercises the true 24-bit threshold
  arithmetic rather than standing in for it.

The pristine model was restored and the corpus re-verified green before committing; no mutant
code is committed.

## Honest scope -- what this does NOT do

- **Sail only.** No RTL touched; no RTL/ACT4 numbers claimed.
- The retirement threshold is now 16.7M reuses per slot, not infinite. Truly unbounded churn
  still needs **sweeping revocation** (DESIGN_06) to reclaim generations/IDs -- widening the
  counter raises the ceiling, it does not remove the need for reclamation. Stated plainly so
  "24 bits" is not mistaken for "solved forever."
- With generation done, the capability format and the ODT entry are now width-consistent. The
  remaining gap is the **ODT index window / segmented-Object_ID** (DESIGN_06): the 44-bit
  namespace is expressible and backable per-entry, but the modeled table is still a bounded
  flat window, so ids above it read as not-found.
