# DESIGN_08 Sail experiment -- domain-segmented Object_ID (the ODT trilemma, validated)

**Date:** 2026-08-11. **Layer:** Sail formal model. **Repos:** model in `Veda-Core-sail-riscv`
branch `phase1-respec`; tests + this doc in `veda-core-sindhu`. **Design authority:**
`veda-core-linux` `design/DESIGN_08_OBJECT_NAMESPACE_SCALE.md`.

## What this closes

DESIGN_08 decided the ODT (Object Descriptor Table -- the master directory of every object)
scale/flat/deterministic trilemma: split the 44-bit Object_ID into `{region:20, local:24}` where
the **region is a protection domain**, keep a small always-resident Region Table (RT), demand-page
each domain's own per-region ODT, and load the current domain's ODT base into a **CRBR
(Current-Region Base Register)** at domain entry so intra-domain binds stay a single read. That
document itself said the decision "needs its own design doc **+ Sail experiment**." This is the
Sail experiment: it proves the mechanism is expressible and machine-checks the three invariants
that make it correct, using the project's existing bounded-window discipline so it compiles.

In plain terms: this is the last open architectural question of Phase 1, and this experiment
turns the paper decision into a running, formally-modeled mechanism -- without yet building RTL.

## What was built (Sail model)

- `region_entry` struct + `veda_region_table : vector(8, region_entry)` -- the RT, flat and
  always resident, one entry per modeled domain: `{rt_valid, region_odt_base, region_resident,
  region_backing, region_generation}`.
- `veda_current_region` + `veda_current_odt_base` -- the **CRBR**. Loaded at domain entry exactly
  as `veda_pcc_base` is; a single architectural register, **not a cache or TLB** (no tags, no
  eviction, no fill-on-miss, no access history).
- `odt_lookup`/`odt_write` rewritten to the two-step resolve: decompose `{region, local}`; use the
  CRBR base for the current region (the one-read fast path) or the RT base otherwise; bound BOTH
  region and local to their modeled windows (bounding local is what stops a local overflow from
  aliasing the next region's slots -- the mechanism behind global uniqueness).
- A new `VEDA_CAUSE_REGION_FAULT` (0x09) and a region-residency gate at the top of Object-Bind: a
  bind into a non-resident domain raises the explicit fault, for all bind modes (a paged-out region
  is recoverable, not a soft-fail "not found").
- The single modeled ODT array (2^23 entries) is partitioned as 8 regions x 2^20 locals = 2^23
  exactly, so **every pre-DESIGN_08 object (all region 0) keeps its old index** and the whole prior
  corpus stays on the one-read fast path, unaffected.

## The three machine-checked invariants

| # | Invariant | How it is proven |
|---|---|---|
| i | **Global uniqueness** -- `{region=A, local=k}` and `{region=B, local=k}` are different objects | `vc_region_uniqueness.S`: binds Object_ID 5 (region 0, local 5) and (1<<24)|5 (region 1, local 5), reads both Bases, asserts each equals its OWN seeded Base (0x80010400 vs 0x80020000) and that they differ. The region genuinely routes the lookup. |
| ii | **Fixed-shape** -- the resident hot path is a fixed-depth resolve, no variable-depth walk | Structural / by construction: `veda_odt_index` is straight-line (decompose, one compare, one base select, one add, one bound) with no loop or recursion. Sail cannot count cycles, so this is proven by the absence of iteration, not a runtime timing test -- stated honestly, not overclaimed. |
| iii | **Explicit fault** -- a non-resident region raises a real trap, never a silent miss | `vc_region_fault_neg.S`: binds (2<<24)|7 in the non-resident region 2, asserts a hard trap with cause 0x09, distinct from OBJECT_NOT_FOUND (0x05) -- the object exists, its table is paged out. |

## Verification

| Stage | Result |
|---|---|
| Baseline before experiment (increment-4 model) | 70/70 |
| Region-table model, full corpus | **72/72** -- 70 prior unaffected + 2 new |

The prior 70 tests are the zero-regression check: all their objects are region 0, so they take the
CRBR fast path and behaved byte-for-byte as before.

**One honest note on the first run:** the uniqueness test initially failed (71/72) because its
first draft bound Object_ID 5 as the region-0 object -- but Object_ID 5 is the pre-existing
Milestone-12 "wrong-owner" seed (owner_hart = 99), so a plain bind of it correctly hard-trapped
with an Owner Violation. That was a bug in the test's object choice, not in the mechanism (the
region-fault test and all 70 prior tests passed on that same run). Fixed by pairing region-1
local-1 against the bindable, unowned Object_ID 1; the mechanism was never at fault.

### Mutation testing (why the invariant tests are not vacuous)

- **Mutant R -- make the non-resident region resident** (`region_resident = false -> true` for
  region 2). Expected: the fault no longer fires, so `vc_region_fault_neg` fails. **Result: 71/72,
  only `vc_region_fault_neg` failed** -- a precise, single-test kill. The explicit-fault invariant
  genuinely depends on the residency bit, and nothing else does.
- **Mutant C -- collapse the region base** (`veda_odt_base_of` always returns 0, so the region no
  longer disambiguates). Expected: `vc_region_uniqueness` fails. **Result: 57/72 -- 15 tests
  failed, and every single one binds Object_ID 1.** This is the honest, stronger outcome (the same
  shape as the increment-3 mutation): collapsing the region base makes the region-1 seed
  (`{region=1, local=1}`) alias Object_ID 1's slot (`{region=0, local=1}`), corrupting it, so
  **every test that binds Object_ID 1 fails** -- verified directly, all 15 bind it. This proves the
  region disambiguation is load-bearing across the whole corpus, not just in the one test written
  for it: without it, distinct Object_IDs collide. `vc_region_uniqueness` is among the 15 and
  catches the collision directly (its two Object_IDs stop resolving to distinct Bases).

The pristine model was restored and the corpus re-verified green (72/72) before committing; no
mutant code is committed.

## Honest scope -- what this experiment does and does NOT establish

- It proves the mechanism is **expressible and its invariants hold in the formal model**. It does
  NOT measure cost: there is still no DRAM-latency model, so the +1 cross-domain read remains
  unmeasured (DESIGN_08 Section 9).
- It uses **bounded modeled windows** (8 regions, 2^20 locals) exactly as the existing ODT is
  bounded to 2^23. It does not model the full 2^20 x 2^24 namespace; it proves the STRUCTURE, not
  the full scale.
- The **region fault is checked at Bind only** in this experiment (the most central "resolve an
  object" point). A full implementation would also gate the dereference paths; that is
  implementation work, not a gap in the mechanism proof.
- The CRBR is modeled as reset-to-region-0. A full implementation loads it at **OCInvoke** domain
  entry; wiring that into OCInvoke is the next implementation step, not part of this expressibility
  proof.
- Everything else in DESIGN_08 Section 9 remains open: the 2^20 domain ceiling, cross-domain
  sharing policy, MSA-private-RT as a verified invariant, region-grant authority, RT-entry MAC, and
  reclamation as a hard prerequisite. This experiment validates the core lookup mechanism; it does
  not close those.

**Sail only. No RTL was touched; no RTL/ACT4 numbers are claimed.**
