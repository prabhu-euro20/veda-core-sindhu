# Phase 1 (Sail respec) -- Increment 1: CAndPerm, rights attenuation

**Date:** 2026-08-11. **Layer:** Sail formal model (Sail-first, per the project's standing
sequencing). **Repos:** model change in `Veda-Core-sail-riscv` (branch `phase1-respec`);
tests + this doc in `veda-core-sindhu`. **Design authority:** `veda-core-linux`
`design/DESIGN_01_CAPABILITY_FORMAT_RESPEC.md`, section "New instruction -- CAndPerm".

## Why this instruction, and why it is first

The 36-instruction set had **no per-holder rights attenuation**. Without it, handing a domain
a read-only view of a live object forces a *separate Object_ID aliasing the same Base* --
which breaks temporal safety, because destroying one ID does not revoke the alias. CAndPerm
derives a weaker capability to the **same live object**: no new Object_ID, no alias, so a
later ODT-Destroy still revokes every view at once.

Chosen as the first Phase-1 increment on four grounds:

1. **Security-first / hardware-native.** It closes a real temporal-safety hole by
   construction rather than by software convention, and it is the enabler the multi-process
   rights model needs (read-only text/data shared to children; DESIGN_02's object-COW fork
   hands parent and child *attenuated* capabilities to the same Object_IDs).
2. **Lowest blast radius.** Purely additive: one new funct7, no change to any existing
   instruction, no change to the capability struct. `Perms` is `bits(16)` in both the current
   and the proposed 256-bit format, so this needs **no rework** when the format respec lands.
3. **Idiom already established.** It is the OCA/CSetBounds "manipulate" family shape, so it
   introduces no new conventions.
4. **De-risks the phase.** It proves the whole clone -> build -> test -> mutation-test loop in
   the new workspace before the much larger 256-bit format change touches every field width.

## What was built

`model/extensions/Veda/veda_cap_insts.sail`, R-type Custom-2 (`0b1011011`), funct3 `0b001`
(capability destination), **funct7 `0b0010111`**.

Slot chosen after enumerating **every** existing user of the Custom-2/funct3=001 space:
OCA `0001010`, CSetBounds `0001000`, CSetBoundsExact `0001001`, CSeal `0010000`, CUnseal
`0010001`, OCInvoke `0010010`, OSpecialRW `0010011`, OCJALR `0010100`, CSealEntry `0010101`,
OCRETURN `0010110`. `0010111` is the next free value. This "grep the whole file before
picking a slot" step is not ceremony: the same project once caught a real, narrow
OCJALR/OSpecialRW collision that would only have bitten encodings with `cs2 = c0`.

Semantics (mirroring the OCA idiom exactly):

- `cd` fields are written **unconditionally**; only the Tag is conditionally cleared.
- `cd.Perms = cs1.Perms & rs2[15:0]`; every other field carried through unchanged.
- Tag cleared iff the source was **untagged** or **already sealed** (a sealed capability's
  rights are frozen; an untagged source can never produce a valid result).
- **No bounds term** -- unlike OCA/CSetBounds. Masking permissions cannot produce an
  out-of-window value, so tag+seal are the only real soft-fail conditions. Stated explicitly
  rather than copying OCA's third term for symmetry's sake.
- **Monotonicity is structural, not checked.** Bitwise AND can only clear bits, never set
  them, so `cd`'s rights are a subset of `cs1`'s by construction -- there is no "did you try
  to grant a permission" check to get wrong.

## Verification

Environment: Sail 0.20.2, `sail_riscv_sim` built from this branch; the frozen line's GCC and
test corpus were used **read-only** (no file in `rva23-core` was modified).

| Stage | Result |
|---|---|
| Baseline (unmodified model, freshly built sim) | **65/65 pass** |
| With CAndPerm + 2 new tests | **67/67 pass** -- 65 baseline **zero regressions**, 2 new pass |

Establishing the baseline on a *freshly built* simulator first was deliberate: it proves the
new workspace reproduces the verified state exactly, so any later failure is attributable to
the change under test and not to the environment.

### Tests

`vc_candperm.S` (positive) -- binds the reset-seeded object, then:

- partial mask: reads the original `Perms` with `cgetperm`, applies `candperm`, and checks the
  result equals `original & mask` **computed at runtime by the test itself** (`and x20, x10,
  x2`) rather than against a hardcoded constant, so the test cannot drift from the seed data;
- checks `Base`, `Length` and the Tag are untouched by attenuation;
- mask = `x0` (clear everything): every permission is gone **and the Tag is still set** --
  attenuating all rights must not invalidate the capability. That is the property that
  distinguishes "weaker" from "destroyed".

`vc_candperm_neg.S` (negative) -- mints a genuinely sealed capability via `CSealEntry`,
sanity-checks that it is valid, then attenuates it and asserts the result's Tag is **0**.

### Mutation testing (why the tests cannot pass vacuously)

Passing tests only prove something if a broken model fails them. Two deliberate mutations were
built and run against the full corpus:

- **Mutant 1 -- ignore the mask** (`new_perms = cap.Perms`, dropping the AND).
  Expected: `vc_candperm.S` fails, nothing else. Result: **66/67 -- only `vc_candperm`
  failed.** The positive test genuinely exercises the AND semantic, and is precise (it did not
  false-fail any of the other 66 tests).
- **Mutant 2 -- drop the seal check** (`wCTag(rdno, CTag(capidx))`, letting a sealed source
  produce a tagged result). Expected: `vc_candperm_neg.S` fails, nothing else. Result:
  **66/67 -- only `vc_candperm_neg` failed.** The negative test genuinely exercises the
  sealed-source soft-fail.

Each mutation killed exactly the one test it was designed to, and no other -- so neither test
passes vacuously, and each pins the specific property it claims to. The pristine model was
restored and the full corpus re-verified green (67/67) before committing; **no mutant code was
committed.**

## Honest scope -- what this does NOT do

- It does not add revocation. CAndPerm attenuates at **derivation time**; it cannot reach back
  and retract a capability already handed out. Selective retraction is DESIGN_07 Rev-A
  (per-object epoch/delegation vector), still unbuilt.
- It does not change the capability format. The 256-bit respec (Object_ID 44 / Base 56 /
  Length 40 / ...) is the next, much larger increment.
- Sail only. The RTL mirror is separate follow-on work, per the project's Sail-then-RTL rule.
- No RTL/ACT4 numbers are claimed here, because no RTL was touched.
