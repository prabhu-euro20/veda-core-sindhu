# Phase 2, increment 2 -- the page-out / page-in pair

**Date:** 2026-08-12. **Layer:** Sail (`veda-core-sail-riscv`, branch `phase1-respec`).
**Implements:** the cached-Base contract decided in `DESIGN_02` ("The cached-Base fork").
**Baseline:** 80/80.

## 1. Why this increment is not `backing`

The plan said increment 2 would add the `backing` field. Grounding it first showed that would have
been motion without progress: `backing` has **no reader** (no instruction in the model reads any ODT
entry field into a register), and it would feed a repair path that **cannot repair**. The blocking
defect was elsewhere.

DESIGN_02's one-line sketch -- "the handler fetches contents from `backing`, allocates physical
Base, sets `resident`, and resumes" -- hides three problems, each deeper than the last:

1. **Populate cannot be the repair primitive.** It bumps `generation` whenever the old entry was
   valid, and a paged-out object is *valid but not resident*. Using it would invalidate every
   capability on every page-in, making demand paging useless.
2. **Capabilities cache `Base`.** The access path computes its address from `cap.Base`, never from
   the live entry. Paging exists to free a frame and give it away, so a returning object comes back
   at a **different** Base -- and the cached copy must therefore be invalidated. That fork is
   settled in DESIGN_02: bump on page-out and let holders re-Bind, rather than removing Base
   caching and paying a DRAM read on every access forever.
3. **The generation ceiling breaks the contract.** Detailed in Section 3 -- it is the security core
   of this increment.

## 2. What landed

Two instructions, sharing `funct7 = 0b0000101` and splitting on `funct3` by operand shape, exactly
as ODT-Populate (`000`) and ODT-Destroy (`001`) already share `0b0000011`. Both encodings were
verified unallocated in Sail **and** in the RTL's own decode before use.

| | `veda.odt.page.out` | `veda.odt.page.in` |
|---|---|---|
| shape | 2-operand (`rs1` = Object_ID) | 3-operand (`rs1` = Object_ID, `rs2` = new Base) |
| gate | `valid & resident & generation != 0xFFFFFF` | `valid & not resident` |
| writes | `resident = false`, `generation + 1` | `Base = new`, `resident = true` |
| preserves | everything else | **everything** else, including `generation` and `owner_hart` |

**Page-in changes exactly two fields.** That is the whole reason it exists as a separate
instruction: Populate would bump `generation` (killing every capability) and reset `owner_hart`
(silently dropping hart ownership across every paging cycle).

### The gate is sound by construction, not by convention

Enumerating every `odt_write` in the model shows page-out is the **sole producer** of
`{valid, not resident}`: Populate and Populate-Fast always write `resident = true`; Destroy writes
`valid = false` alongside `resident = false`; the Bind/Rebind claim carries residency over unchanged
*and* is preceded by increment 1's residency gate, which traps before the write is reached. So
"you may only page in something a page-out produced" is a structural fact.

That is what makes a generation-preserving Base write safe: between page-out and page-in, no
capability carrying the current generation can exist, because capabilities take their generation
only from a Bind and Bind hard-traps on exactly that state for all three of its modes.

### No new authority is granted -- it is strictly tightened

Composed, page-out then page-in is observationally equal to one ODT-Populate-Fast (net generation
+1, arbitrary new Base, resident), under the same authority gate. The pager already holds that
power. The two field-level differences both **restrict** it: Populate resets `owner_hart` and lets
`veda_attr` re-permission the object; page-in preserves `owner_hart`, `Length` and `Perms`.
**Paging an object may move it; it may not re-authorize it.**

## 3. The security core: the saturation refusal

The entire safety argument rests on one thing -- page-out's generation bump invalidates every
outstanding capability. But `generation` **saturates** at `0xFFFFFF` rather than wrapping.

At saturation the bump becomes a silent no-op. Page-out would clear residency while invalidating
nothing; page-in would then restore residency at a **new** frame while every outstanding capability
still matched on generation; and each would compute its address from its own stale cached `Base`,
reading and writing the **freed** frame now owned by another object. A full use-after-free -- the
exact attack the pair exists to prevent, reappearing at the boundary.

`retired` does not intercept it. A Destroy from `0xFFFFFE` leaves generation `0xFFFFFF` with
`retired` still **false** (its rule tests the *old* generation), and a following Populate is then
permitted and leaves the slot valid, resident, saturated and un-retired. That is a reachable state,
traced in the model rather than hypothesised.

**Decision: page-out refuses once generation is saturated.** If the invalidation mechanism cannot
run, the operation that depends on it must not proceed. Fail closed. The refusal is placed on
page-out rather than page-in because page-out is the instruction making the promise. The cost is
that a pager cannot evict one exhausted object; the alternative cost is the temporal-safety
guarantee of the whole design.

## 4. Verification

| Stage | Result |
|---|---|
| Baseline before the pair | **80 / 80** |
| Pair landed, first two tests | **82 / 82** |
| First mutation sweep | **2 killed, 4 survived** |
| Two more tests, closing all four | **84 / 84** |
| Re-run sweep | **6 killed, 0 survived** |

Four tests, four distinct claims:

1. **`vc_paging_full_cycle`** -- the whole contract end to end: bind, use, page-out, stale trap,
   re-Bind, page-in at a **different** frame, use again at the new location. Two real
   linker-allocated buffers, so "the object moved" is a fact about addresses. It asserts old Base
   != new Base, without which a page-in that ignored its Base operand would still pass.
2. **`vc_paging_saturation_neg`** -- the refusal at the generation ceiling, driven to the boundary
   by the real reachable sequence rather than a hand-placed state, and asserting the refused
   page-out did not half-apply.
3. **`vc_paging_refusals_neg`** -- page-in refuses a **live** object; page-out refuses an
   **already paged-out** one; neither half-applies.
4. **`vc_paging_preservation`** -- `generation` and `owner_hart` both survive a paging cycle.

### Mutation testing, both passes

| Mutant | Property | First pass | After the new tests | Test that kills it |
|---|---|---|---|---|
| M1 saturation refusal removed | refusal | KILLED | **KILLED** | `saturation_neg`, `preservation` |
| M2 page-out does not bump | mechanism | KILLED | **KILLED** | `full_cycle`, `saturation_neg`, `preservation` |
| M3 page-in bumps generation | preservation | *survived* | **KILLED** | `preservation` |
| M4 page-in accepts a live object | refusal | *survived* | **KILLED** | `refusals_neg` |
| M5 page-in resets `owner_hart` | preservation | *survived* | **KILLED** | `preservation` |
| M6 page-out accepts a paged-out object | refusal | *survived* | **KILLED** | `refusals_neg` |

**The first pass is the more useful result of the two.** 82/82 green with four of six mutants
surviving is exactly the state that looks finished and is not. Every survivor was a *refusal* or a
*preservation* -- the tests proved the mechanism works and caught one boundary, but almost nothing
about what the instructions decline to do, which is where a security primitive's value concentrates.

M5 is worth singling out: it is a **multi-hart** property proven in a **single-hart** model. Page-out
is gated on ODA authority rather than ownership, so a pager may legitimately evict an object it does
not own; had page-in reset `owner_hart`, any hart could then claim it -- object theft by triggering a
page fault. That would have stayed invisible until multi-hart landed, by which point it would be a
live hole in shipped hardware.

### The fixture detail that decided M3

`vc_paging_preservation` uses a fixture seeded at `0xFFFFFD`, **two** steps below the ceiling, not
one. At `0xFFFFFE` a wrongly-bumping page-in **saturates** to `0xFFFFFF`, which is indistinguishable
from correctly preserving it -- the mutation hides inside the saturation. Two steps down, the
behaviours separate into something countable: two successful page-outs before the refusal if
generation is preserved, one if it is bumped. `generation` is architecturally unreadable by design
(there is no CGet for it), so counting the refusal boundary is the only available observable.

This is the third instance of the same shape in Phase 2, and the pattern is worth stating plainly:
**ask not whether the test gets the right answer, but whether it can distinguish the wrong one.**
Increment 1 needed the saved-shadow read to happen *before any trap* (afterwards the mutant and the
correct design converge), and needed a test that actually *dereferences* to reach the dereference
gate. Here the fixture had to sit one step further from the boundary. In all three the correct and
incorrect designs agree everywhere except at one carefully chosen point.

## 5. What mutation testing found, and why it matters more than the pass count

The first two tests -- the full cycle and the saturation boundary -- gave **82/82**. Mutation gave
**2 killed, 4 survived**, and the pattern in the survivors is the real finding:

| Mutant | Property | First pass |
|---|---|---|
| M1 saturation refusal removed | refusal | **KILLED** |
| M2 page-out does not bump | mechanism works | **KILLED** |
| M3 page-in bumps generation | *preservation* | survived |
| M4 page-in accepts a live object | *refusal* | survived |
| M5 page-in resets `owner_hart` | *preservation* | survived |
| M6 page-out accepts a paged-out object | *refusal* | survived |

**Every survivor is a refusal or a preservation.** The tests proved the mechanism *works* and caught
*one* boundary, but almost nothing about what the instructions **refuse to do** -- which is where
most of a security primitive's value lives. M4 is the sharpest: it removes the only thing preventing
an authorized pager from silently relocating a **live** object while preserving generation, so every
outstanding capability keeps validating and nothing signals the move. Doing the same through
Populate would bump generation and make the relocation loud.

Two further tests close all four. One detail from building them is worth keeping:

**The generation fixture sits at `0xFFFFFD`, two steps below the ceiling, not one.** At `0xFFFFFE`
a wrongly-bumping page-in would *saturate* to `0xFFFFFF`, which is indistinguishable from correctly
preserving it -- **the mutation hides inside the saturation**. Two steps down, the behaviours
separate into a countable difference: two successful page-outs before the refusal if generation is
preserved, one if it is bumped. This is the same shape as increment 1's saved-shadow read, which had
to happen *before any trap* because afterwards the mutant and the correct design converge.

## 6. A process failure, repeated

Test files were created **while a mutation sweep was still running**, for the second time in this
phase. The runner globs `vc_*.S`, so they entered the corpus mid-run and made the sweep's final
pristine re-verify report `82/84` against a binary that predated the fixtures they need. The six
mutant verdicts were unaffected -- those completed while the corpus was frozen at 82 -- but the
closing number was worthless and the whole suite had to be re-verified independently.

The rule was already written down after increment 1 and was still broken. Writing a rule down is not
the same as following it. Concrete change, rather than another resolution: **record the corpus file
count before a sweep and assert it afterwards**, so a mid-run change is detected mechanically
instead of noticed by luck.

## 7. Honest scope

- **`backing` is still not built**, and now has a clear prerequisite list rather than a vague one:
  it needs a reader (no instruction reads any ODT entry field today), a decision on what it denotes
  (the apparent in-tree precedent `region_backing` turns out to be an unexamined placeholder with
  zero readers), and a handler-side way to identify which object faulted (`mtval` carries
  `{cap_idx, cause}`, not an Object_ID).
- **Paging is not transparent, by design.** A holder whose object was paged out sees a trap and must
  re-Bind. This is the accepted cost of the DESIGN_02 decision, not an oversight.
- **Each page-out consumes one of 2^24 generations** for that slot. A hot, frequently-paged object
  approaches retirement, so reclamation (DESIGN_07 Rev-B) is a harder prerequisite than the original
  sketch implied.
- **Region residency is not checked** by page-out/page-in, inheriting the existing behaviour of the
  Populate/Destroy family (only Bind checks it). Deliberately consistent rather than diverging here,
  but it means an object can be paged into a domain whose own table is paged out. Should be settled
  for the whole family at once.
- **RTL is now two increments behind Sail** -- neither `resident` nor this pair is mirrored.
- **Execution-side capabilities never re-consult the ODT**, so PCC is outside this mechanism
  entirely. Not a gap this increment creates, but worth stating where the boundary is.
