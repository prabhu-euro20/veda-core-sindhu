# RTL mirror -- Increment 2b: the 256-bit capability format

**Date:** 2026-08-11. **Layer:** RTL (`veda_core.tlv`). **Branch:** `sindhu`. **Mirrors:** the
Sail-verified increment 2 (`PHASE1_SAIL_RESPEC_256BIT_RESULTS.md`) and DESIGN_01's layout table.

## What changed

The capability register file and every consumer of it widen to the respec layout:

| Field | Was | Now |
|---|---|---|
| Object_ID | 23 | **44** |
| Base | 32 | **56** |
| Length | 16 | **40** |
| Offset | 16 | **40** |
| Perms | 16 | 16 |
| otype | 16 | 16 |
| Reserved (generation) | 8 | **24** |
| flags | -- | **20 (new, opaque)** |

44+56+40+40+16+16+24+20 = **256 exactly**, so the old 127-data-bits-plus-`1'b0`-pad memory image
is gone: the pack drops the pad term and the unpack drops its bit-0 skip.

Concretely: the seven `/vreg` field declarations and their reset literals; a new `$flags` field
(minted `20'b0` by every producer, restored from memory by OCL.C so the round-trip matches Sail's
struct pack/unpack rather than diverging the day flags gains meaning); the `$veda_rs1cap_*`,
`$veda_cs2_*`, `$veda_ocsc_store_cap_*` and `$veda_oclc_unpacked_*` read signals; the three
Special Capability Registers (ODA/TSC/SSC, 5 fields each); the zero-extends feeding the bounds,
OCA and CGet* paths; and -- the highest-risk part -- the **raw `\SV` `always_ff` OCS.C store
blocks**, which now write **32 bytes per arm** instead of 16, and the OCL.C load which reads 32.

## Why this needed an inventory first, not just edits

Sail's type checker turned every missed width into a compile error -- that was the tripwire that
made the Sail respec safe. **Verilog has no such tripwire: a signal left at its old width silently
truncates, compiles clean, and produces wrong values.** So every consumer was found by reading the
file, not by relying on the build to complain, and the edits were followed by a grep-based
re-verification of the specific sites that would fail silently:

- `oca_sum[15:0]` (would have capped the cursor at 16 bits, wrapping every pointer past 64 KB): 0
  remaining.
- `packed[127` / `load_data[127` (old pack/load widths): 0 remaining.
- OCS.C byte-write count per arm: **32 and 32**, verified by counting; the highest packed slice
  referenced is `[255:...]`. If only 16 had been written the top 16 bytes of every stored
  capability would be stale, with no diagnostic anywhere.
- OCL.C byte-read count per arm: **32 and 32**.
- The unpack bit ranges were transcribed from DESIGN_01 character by character, **not re-derived
  from field widths** -- Perms `[75:60]` and otype `[59:44]` are exactly the two a width-driven
  review skips, because their widths did not change but their positions moved.

### Deliberate interim narrowings, marked

The ODT entry is still the pre-respec layout (RTL-3 widens it), so Bind still names a slot with 23
bits and the id_hi anti-alias tag is still 15 bits. In Verilog a deliberate narrowing and a
forgotten widening are textually identical, so all four such sites carry an explicit
`INTERIM BRIDGE RTL-3:` marker. **`grep 'INTERIM BRIDGE'` must reach zero when RTL-3 lands** -- that
grep is the substitute for the type error Verilog will not give us.

## Verification

| Stage | Result |
|---|---|
| Before RTL-2b (after RTL-2a) | 57/57 |
| RTL-2b, full suite | **58/58** (57 + the new round-trip test) |

**Zero regression is necessary but not sufficient here, and it is worth being precise about why:**
every existing capability test reads through CGet*, and those return the *same numeric values*
under wider zero-extends whether or not the new 256-bit layout is correct. A completely wrong
pack/unpack layout could still show 57/57. So a test was written specifically to catch that:

- `veda_smoke_cap256_roundtrip.S` -- stores a capability with a **nonzero, mid-layout Offset
  (0x18)** to memory and reloads it, then compares **every** field before vs after. Observed:
  `base=0x80010000 len=0x40 perm=0x100c type=0xffff off=0x18` identical on both sides, tag=1.

### Mutation testing

- **Mutant U -- shift the Offset unpack window by one bit** (`[115:76]` -> `[116:77]`), a classic
  off-by-one in a 256-bit layout. **Result: `cap256_roundtrip` FAILED; `cap_granule_tamper` PASSED;
  and `m7` -- the pre-existing OCL.C/OCS.C round-trip test -- also PASSED.**

That m7 result is the point of the whole exercise: **the existing suite genuinely cannot detect a
wrong capability layout**, and the new test can. The mutation is also precise -- it broke only the
test that checks field exactness. Pristine RTL restored and the full suite re-verified before
committing; no mutant code is committed.

## Honest scope

- The **ODT entry is unchanged** in this increment, so an object still cannot actually *have* a
  Base above 4 GiB or a Length above 64 KiB -- the capability can now express one, but the table
  cannot supply one. That is exactly the state Sail was in after its increment 2, and RTL-3 fixes it.
- The four `INTERIM BRIDGE RTL-3` sites are live narrowings, deliberately.
- PCC/mepcc and `veda_attr` are still narrow (RTL-3 scope), as are the ODT-side generation and
  populate paths (RTL-3/RTL-4).
- RTL only; no ACT4 numbers claimed (the conformance suite is pure GPR datapath).
