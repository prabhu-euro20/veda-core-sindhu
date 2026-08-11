# Phase 1 (Sail respec) -- Increment 2: the 256-bit capability format

**Date:** 2026-08-11. **Layer:** Sail formal model (Sail-first). **Repos:** model change in
`Veda-Core-sail-riscv` branch `phase1-respec`; tests + this doc in `veda-core-sindhu`.
**Design authority:** `veda-core-linux` `design/DESIGN_01_CAPABILITY_FORMAT_RESPEC.md`.

## What changed

The capability widened from 128 bits to **256 bits**, removing all four spec-level walls that
made Linux-scale objects literally inexpressible:

| Field | Was | Now | Wall removed |
|---|---|---|---|
| Object_ID | 23 | **44** | 8.4M live objects |
| Base | 32 | **56** | 4 GiB physical ceiling |
| Length | 16 | **40** | 64 KiB max object |
| Offset | 16 | **40** | (tracks Length) |
| Perms | 16 | 16 | -- |
| otype | 16 | 16 | -- |
| `Reserved` | 8 | **`generation` 24** | 255 destroy/reuse then retirement |
| -- | -- | **`flags` 20** | new, opaque/reserved |

44+56+40+40+16+16+24+20 = **256 exactly**, so the old 127-bit-plus-pad layout is gone: pack and
unpack were re-derived field-by-field, not width-patched, and the pad bit (and the unpack's
bit-0 skip) no longer exist.

## The two decisions that overrode earlier design text

Both were adversarially derived and are recorded in full in DESIGN_01.

### 1. The tag granule widens 16 -> 32 bytes (overrides "granule size stays")

A 256-bit capability is 32 bytes. With a 16-byte granule it would span **two** granules, but
the tag store reads a **single bit at the access's own granule** (`__ReadRAM_Meta`). Because
the field layout puts **Perms, otype and generation in the low half (bytes 16..31)**, an
ordinary store into that half would clear only the *second* granule's tag while the load kept
reading the *first* -- still 1. The result: a capability that loads as **valid** with
attacker-rewritten permissions, an unsealed otype, and a reset generation. That is a complete
forgery primitive, and it would have defeated Tag unforgeability -- the pillar the whole model
rests on.

Widening the granule keeps "one capability occupies exactly one granule" true by construction,
so any tampering store lands in the granule the load actually checks. Region coverage is
unchanged (16384 x 32 = 0x80000 bytes, verified arithmetically).

### 2. `Ext_Veda` is now RV64-only (reverses the earlier xlen-generic decision)

Base(56), Object_ID(44), Length(40) and Offset(40) all exceed 32 bits, so
`zero_extend(field) : xlenbits` is ill-typed whenever `xlen` could be 32 -- and this codebase
had already learned that an encdec `when ... & xlen == 64` guard is **not visible to the type
checker inside an execute body**. Capability address arithmetic is therefore done in an
explicit 64-bit domain and narrowed once, through a single helper (`veda_to_xlen`), which is
well-typed for both xlen values because `core/xlen.sail` constrains `xlen in {32, 64}`.

Honest consequence, stated rather than buried: **there is no RV32 Veda-Core under this
format**, and NMC_ADD.W is lost on RV32. This is not a quirk of choosing 256 bits -- DESIGN_01's
own "area-conscious 192-bit alternative" (Base 48 / Object_ID 40) exceeds 32 bits too. Only a
compressed 128-bit format could restore RV32, and that is a separate, deferred decision.

## Other resolved decisions

- **ODT stays narrow this increment.** Bind zero-extends the still-32/16/8-bit ODT entry into
  the wide capability -- lossless, since a 32-bit Base *is* a valid 56-bit Base. This keeps the
  atomic change smaller and defers the genuinely separate ODT-Populate operand redesign
  (Base56+Length40+Perms16 = 112 bits no longer fits one GPR). **The ODT's own widths remain
  the real limit on what an object can be**, regardless of what the format can now express.
- **PCC also stays narrow this increment**, with an explicit truncation at the two assignment
  sites. Provably lossless *because* the ODT is still narrow, and it reproduces the previous
  model's behaviour exactly -- which is what keeps the verified baseline meaningful instead of
  merely passing. PCC widens in the same increment as the ODT, because that is when wider
  values can first exist and when the `VEDA_PCC_UNBOUNDED` sentinel value must change.
- **ODT index domain is a bounded window.** The capability carries a full 44-bit Object_ID, but
  a flat `vector(2^44)` is ~300 TiB and will not build; ids at or above the modeled size read
  as not-found. The explicit bound check is also what discharges Sail's in-bounds proof
  obligation now that the index domain and the array size are decoupled.
- **`flags` is opaque/reserved**, minted as zeros by Bind. Assigning bit positions (especially
  a CID width) before the DESIGN_00 namespace work would be an under-sourced guess.
- **`PERM_ATTENUATE` was deliberately NOT added.** CAndPerm is monotonic -- it can only remove
  rights -- so requiring a permission to *give away* permissions is meaningless, and real
  CHERI's CAndPerm is ambient for the same reason. Reserving a permission bit with no consumer
  would violate this project's own "speculative, not grounded" rule.
- **otype representability guard.** `Offset` is now 40 bits while `otype` stayed 16, so
  CSeal/CUnseal/OCJALR no longer type-match. A naive `[15..0]` truncation would have
  **reintroduced sentinel forgery** (Offset 0x1FFFF aliasing UNSEALED_OTYPE, 0x1FFFE forging
  VEDA_OTYPE_SENTRY -- exactly the hole Milestone B closed). CSeal now requires
  `unsigned(Offset) <= 65535` *before* narrowing; CUnseal and OCJALR compare in the wide domain,
  where an out-of-range Offset simply fails authorisation. Honest scope: this guard is
  **currently unreachable**, because the narrow ODT caps Length at 0xFFFF and authorisation
  already requires Offset < Length. It becomes load-bearing the moment the ODT widens -- it is
  future-proofing placed now, deliberately, not a tested-today property.

## Verification

| Stage | Result |
|---|---|
| Baseline before the increment (CAndPerm model) | 67/67 |
| 256-bit model, full corpus | **69/69** -- 66 pre-existing green, 1 updated (below), 2 new |

**One pre-existing test needed a real ABI update, stated plainly rather than buried:**
`vc_ocsc_bind_spill_restore_roundtrip.S` created a **16-byte** spill object and 16-byte-aligned
storage. A capability is now 32 bytes, so OCS.C into a 16-byte object is legitimately
out of bounds -- **the model correctly refused it**. The test now declares a 32-byte,
32-byte-aligned spill slot. This is a genuine consequence every capability-spilling ABI must
follow, not a test fudge; the test's intent (spill and restore must preserve the tag) is
unchanged.

### New tests

- `vc_cap_granule_tamper_neg.S` -- **the security property behind override 1.** Stores a tagged
  capability, then does an *ordinary* data store into byte 16 of it (the half carrying
  Perms/otype/generation), then reloads: the tag must be gone.
- `vc_cap_misaligned_neg.S` -- OCS.C at offset 16 hard-traps with the new
  `VEDA_CAUSE_CAP_MISALIGNED` (0x08). Offset 16 is deliberately still *in bounds*
  (16+32 = 48 <= 64), so the trap must come from the alignment rule itself.

### Mutation testing

- **Mutant G -- revert the tag granule to 16 bytes** (i.e. exactly the design the override
  rejected). Expected: the forgery test fails, proving the tampered capability would have kept
  a valid tag. **Result: 68/69 -- only `vc_cap_granule_tamper_neg` failed.**

That result is the whole justification for override 1, and it is empirical rather than
argued: under a 16-byte granule the tampered capability **loads back with a valid tag**, so a
plain store really can rewrite a stored capability's Perms, otype and generation and have the
hardware still accept it. Under the 32-byte granule the same sequence yields an untagged
capability. The mutation also killed *exactly one* test and left the other 68 untouched, so
the new test pins that specific property rather than passing vacuously.

The pristine model was restored and the corpus re-verified green before committing; no mutant
code is committed.

## Honest scope -- what this does NOT do

- **Sail only.** No RTL was touched; no RTL or ACT4 numbers are claimed.
- **The wide fields are not yet reachable end-to-end.** Because the ODT stays narrow, no bound
  capability can actually carry a Base above 4 GiB or a Length above 64 KiB yet. The *format*
  can express them; the *table* cannot supply them. That is the next increment's job, and
  until then the walls are removed on paper, not in behaviour.
- Object_IDs above the modeled ODT window read as not-found rather than resolving.
