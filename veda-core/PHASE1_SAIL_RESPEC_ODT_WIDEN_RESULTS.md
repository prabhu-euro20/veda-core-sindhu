# Phase 1 (Sail respec) -- Increment 3: widen the ODT entry, populate, and PCC

**Date:** 2026-08-11. **Layer:** Sail formal model. **Repos:** model in `Veda-Core-sail-riscv`
branch `phase1-respec`; tests + this doc in `veda-core-sindhu`. **Design authority:**
`veda-core-linux` `design/DESIGN_01_CAPABILITY_FORMAT_RESPEC.md`.

## Why this increment matters

Increment 2 widened the capability *format* but left the ODT entry narrow, so the four walls
were removed **on paper only**: a bound capability still could not carry a Base above 4 GiB or
a Length above 64 KiB, because the table it was populated from could not supply one. This
increment widens the table, so the walls fall **in behaviour**.

| Field | Increment 2 | Increment 3 |
|---|---|---|
| `odt_entry.Base` | 32 | **56** |
| `odt_entry.Length` | 16 | **40** |
| `veda_attr` (CSR 0x7C4) | 32 | **64** (Length[55:16] \| Perms[15:0]) |
| `veda_pcc_base` / `veda_mepcc_base` | 32 | **56** |
| `veda_pcc_length` / `veda_mepcc_length` | 16 | **40** |
| `VEDA_PCC_UNBOUNDED` | 0xFFFF | **0xFFFFFFFFFF** |

`odt_entry.generation` deliberately stays 8 bits (see below).

## The two populate paths, now clearly split

- **Plain `veda.odt.populate`** keeps its packed single-GPR descriptor and is now explicitly
  the **compact** form: Base 32 / Length 16, zero-extended into the wide entry. 112 bits of
  Base(56)+Length(40)+Perms(16) cannot fit one GPR, so rather than invent a multi-operand
  encoding, the compact form is kept for the ordinary small-object case -- and **every existing
  program keeps working unchanged**. The limit lives visibly in the encoding, not as a silent
  truncation of a wide value.
- **`veda.odt.populate.fast`** becomes the **wide** path: Base at full 56-bit width from a GPR,
  Length(40)/Perms(16) from the widened `veda_attr`. This is the only way to create an object
  larger than 64 KiB or based above 4 GiB.

`veda_attr` was widened **backward-compatibly by construction**: Length occupies [55:16] and
Perms [15:0], i.e. Length's low end stays at bit 16 and grows upward, so a program that wrote a
32-bit attr value yields exactly the same Length and Perms as before (the new high bits it
never set read as zero). That is why no existing fast-populate program needed touching.

## Decisions made in this increment

- **Generation widening (8 -> 24) is deferred to its own increment.** It is genuinely
  independent of Base/Length -- the capability's 24-bit generation is fed by a lossless
  zero-extend from the 8-bit ODT field, so nothing forces them to move together. Widening it
  changes the retirement threshold from 256 to ~16.7M destroy/reuse cycles, which the existing
  saturation tests (`vc_gen_retire*`) reach by **looping**. A 16.7M-iteration loop is not a
  test, so this needs its own increment *and* its own answer for how to exercise a threshold
  too large to loop to. Bundling it here would have forced either deleting those tests or
  running an infeasible loop -- neither honest.
- **PCC had to widen in the same change as the ODT**, not later. Once an object can have a Base
  above 4 GiB, narrowing it into a 32-bit PCC on `OCInvoke` would silently mis-bound the
  compartment -- a real escape. So the truncations increment 2 left at the two PCC-assignment
  sites are removed here, and the bounds flow across at full width.

## A real design wart this increment surfaced (recorded, not silently fixed)

The sentinel value change forced converting every test that used the idiom "`OCInvoke` through
a code object whose Length is 0xFFFF to return PCC to unbounded." That idiom worked incidentally
only because 0xFFFF was both a plausible Length literal and the sentinel; at 40 bits it is a
genuine 65535-byte bound, and -- more tellingly -- **the compact populate descriptor can no
longer express the sentinel at all** (its Length field is 16 bits). Needing to synthesise a
specially-shaped max-length object just to say "return from this compartment" is a smell.
`design/DESIGN_01` now records this as an open question for its own increment: should `OCRETURN`
**restore** the saved bounds (there is precedent in the `veda_mepcc` trap path) rather than
take them from an operand? This is flagged, not fixed, so the awkwardness is not normalised
away by having "fixed" the tests.

## Verification

| Stage | Result |
|---|---|
| Baseline before increment (256-bit model) | 69/69 |
| Increment 3, full corpus | **70/70** (67 prior + 2 granule/misalign + 1 new large-object) |

### The 16 sentinel-cascade test updates -- diagnosed, not assumed

Widening the sentinel broke 16 tests. Every one was **diagnosed against the running simulator
before being touched**, via 16 parallel agents each under a hard rule: *if the failure is not
explained by the sentinel width change, do not invent a fix -- report a suspected real model
bug and leave the file alone.* **Zero suspected real bugs** were reported; all 16 were the
documented semantic change (a stale `0xFFFF` sentinel comparison, or the max-length-object
idiom that now needs the wide populate path). No assertion was relaxed, no check removed, no
trap expectation altered -- each fix preserved the exact property the test proves. The full
corpus was then **independently re-run green (70/70)** rather than trusting the per-agent
reports.

### New test

- `vc_large_object.S` -- **the wall actually falling.** Creates a 128 KiB object (twice the old
  64 KiB ceiling) through the wide populate path, reads its Length back as the full 0x20000,
  reads and writes a byte at offset 0x18000 (far beyond the old 0xFFFF limit, an offset that
  was previously *unrepresentable*), and confirms the bound is still enforced at the new larger
  limit (offset 0x20000 hard-traps with a Bounds Violation). A widened field is only meaningful
  if the check widened with it, so the test asserts both the new reach and the new bound.

### Mutation testing

- **Mutant L -- revert `odt_entry.Length` to 16 bits.** Result: **does not build.** This is a
  coupling signal, not a test kill: Bind now assigns `Length = e.Length` directly into the
  40-bit capability field, so a 16-bit entry field is a type error. Reported honestly as such
  rather than dressed up as a passing mutation -- a build that fails cannot be run, so it proves
  the widths are coupled, not that a test catches anything.
- **Mutant P -- truncate `populate.fast` Length to 16 bits of information** (keeping the field
  40 bits wide so the model still builds). I expected only `vc_large_object` to fail. It killed
  **9 tests (61/70)**, and the extra kills are the honest, more informative result: every one
  of the 9 uses `populate.fast`, and every test that does *not* use `populate.fast` passed. The
  8 beyond `vc_large_object` are exactly the sentinel-cascade tests that were converted to the
  wide populate path -- they create an unbounded code object with Length `0xFFFFFFFFFF`, which
  under the mutant truncates to a finite `0xFFFF` bound, so returning into it leaves PCC bounded
  and the halt store traps. Verified directly: the 9 failures all contain a `populate.fast`
  encoding, and the passing sentinel-fixes (constant-only, no `populate.fast`) do not. So the
  mutation proves the wide Length flowing through `populate.fast` is genuinely load-bearing
  across the corpus, not just in the one test written to exercise it -- a stronger result than
  the single-test kill I predicted, and fully explained rather than surprising.

The pristine model was restored and the corpus re-verified green before committing; no mutant
code is committed.

## Honest scope -- what this does NOT do

- **Sail only.** No RTL touched; no RTL/ACT4 numbers claimed.
- **generation is still 8 bits**, so the retirement wall (255 destroy/reuse per slot) is *not*
  yet removed -- that is increment 4.
- The modeled ODT is still a bounded index window (ids at or above 2^23 read as not-found); the
  44-bit namespace is expressible in a capability but not yet fully backable by the table. That
  is the segmented-Object_ID work (DESIGN_06), still open.
