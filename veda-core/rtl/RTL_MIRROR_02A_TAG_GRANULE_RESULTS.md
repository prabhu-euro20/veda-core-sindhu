# RTL mirror -- Increment 2a: 32-byte tag granule + capability-access alignment

**Date:** 2026-08-11. **Layer:** RTL (`veda_core.tlv`). **Branch:** `sindhu`. **Mirrors:** the
Sail-verified 256-bit respec's granule/alignment decisions (`PHASE1_SAIL_RESPEC_256BIT_RESULTS.md`,
DESIGN_01 decisions 1 and 2).

## The decision that shaped this increment: granule BEFORE format

Sail landed the granule widening and the 256-bit format in one increment. **RTL deliberately does
not.** This is the one place the RTL mirror departs from Sail's increment boundary, and the reason
is specific to hardware:

If the 256-bit format landed first, there would be a window where a 32-byte capability lives in
16-byte granules -- `OCS.C` writes 32 bytes but sets only `tag_mem[addr >> 4]`, so the exact
forgery primitive this respec exists to close would be **wide open**. And the test suite would not
notice: `veda_smoke_m7.S`'s round-trip arm passes *and* its "a plain store clears the tag" negative
arm passes, because a plain store at a low offset still hits the same start granule. **A green
suite over an open security hole is the worst possible state**, so the granule lands first. The
reverse ordering has no such window: it produces exactly one visible, expected failure (below).

In Sail this ordering did not matter, because the type checker forced every consumer to be updated
in the same change. Verilog offers no such guarantee: **a missed width silently truncates and
compiles clean.** That difference is the whole reason this increment exists separately.

## What changed

- **Tag granule 16 -> 32 bytes**, so one capability will occupy exactly one granule once the format
  widens. Four shift sites (`>> 4` -> `>> 5`): the capability-memory granule, the TCM-scratch
  granule, the NMC granule, and -- 1250 lines away in the base-ISA datapath -- the plain-store
  granule. Missing that last one would have meant a plain `sd` clearing the wrong granule.
- **Tag arrays halve**: `tag_mem` and `tcm_scratch_tag` sized `SIZE/32` instead of `SIZE/16`
  (same coverage, one bit per 32 bytes), with their zero-init loops matched.
- **32-byte natural alignment for OCL.C/OCS.C**, enforced as a hard trap with the new cause
  **0x08** (`VEDA_CAUSE_CAP_MISALIGNED`, matching Sail; 0x08 verified free in the RTL cause space).
  Checked after Tag/Seal/Perm and before the bounds fall-through, so a bad capability still reports
  its real reason first. **Scoped to capability accesses only** -- `OCL.D`/`OCS.D` ordinary data
  accesses are untouched, verified by reading their violation expressions directly.

## Verification

| Stage | Result |
|---|---|
| Baseline (before R2a) | 53/53 TEST PASSED |
| R2a, first run | 52/53 -- exactly one failure, `m24_ocsc_tcm`, as the plan predicted |
| R2a, after the expected test update | 53/53 |
| Full suite incl. 2 new R2a tests + 2 CAndPerm tests | **57/57** |

**The one expected test update, stated plainly:** `veda_smoke_m24_ocsc_tcm.S` probes two
never-written capability slots at offset `0x10` to prove they read back untagged. Under a 32-byte
granule, `0x10` is no longer a legal capability address -- it hard-traps as misaligned. Both probes
moved to offset `0x20`, which is 32-byte aligned, still in bounds (`0x20 + 32 = 0x40` = the
object's Length), and still an offset nothing ever wrote. **The property under test is unchanged**;
this is a real ABI consequence every capability-placing program must follow, not a test fudge.

### New tests

- `veda_smoke_cap_granule_tamper.S` -- **the security property.** Stores a tagged capability, then
  does an *ordinary* data store into byte 16 of it (the half that will hold Perms/otype/generation
  once the format widens), then reloads: the tag must be gone. Observed `roundtrip_tag=1
  after_tamper_tag=0`.
- `veda_smoke_cap_misaligned_neg.S` -- a misaligned `OCS.C` at offset 16 hard-traps with
  `mcause=0x18`, `mtval=0x08`, and does not fall through. Offset 16 is deliberately still **in
  bounds** (16 + 32 = 48 <= 0x40), so the trap must come from the alignment rule itself.

### Mutation testing

- **Mutant G(rtl) -- revert the granule to 16 bytes** (the design this increment rejected).
  **Result: `cap_granule_tamper` FAILED, `cap_misaligned_neg` PASSED.** The forgery test genuinely
  depends on the granule width -- under 16 bytes the tampered capability really does load back
  **tagged**, which is the hole, demonstrated in hardware rather than argued on paper. The
  mutation is precise: the alignment trap does not depend on granule width, so that test correctly
  stayed green. Pristine RTL restored and the full suite re-verified before committing; no mutant
  code is committed.

## Honest scope

- The capability is **still 128 bits** in this increment. The granule is now 32 bytes ahead of the
  format, which is safe (a 16-byte capability inside a 32-byte granule is merely coarser tag
  invalidation -- fail-safe), and it is what closes the window described above. The format widens
  in R2b.
- The alignment requirement is live **now**, which is why `m24_ocsc_tcm` needed its offsets fixed;
  any future test placing a capability must use 32-byte-aligned offsets.
- RTL only. No Sail change; no ACT4 numbers claimed (the 51/51 conformance suite is pure GPR
  datapath and is not touched by capability-tag changes).
