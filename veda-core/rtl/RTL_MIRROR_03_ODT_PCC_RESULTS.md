# RTL mirror -- Increment RTL-3: ODT entry, populate split, PCC widen

**Date:** 2026-08-12. **Layer:** RTL (`veda_core.tlv`). **Branch:** `sindhu`. **Mirrors:** the
Sail-verified increments 3 and 4 (`PHASE1_SAIL_RESPEC_ODT_WIDEN_RESULTS.md`,
`PHASE1_SAIL_RESPEC_GENERATION_RESULTS.md`).

## What changed -- the walls fall in behaviour

RTL-2b widened the capability *format*, but the ODT entry stayed pre-respec, so an object still
could not actually **have** a Base above 4 GiB or a Length above 64 KiB. This increment widens the
table that supplies those fields.

**ODT entry 16 -> 32 bytes**, every field byte-aligned:

| Field | Bits | Bytes |
|---|---|---|
| Base | 56 | +0..+6 |
| Length | 40 | +7..+11 |
| Perms | 16 | +12..+13 |
| generation | 24 | +14..+16 |
| valid | 1 | +17 |
| owner_hart | 8 | +18 |
| retired | 1 | +19 |
| id_hi (Object_ID[43:8]) | 36 | +20..+24 |

25 bytes used, 7 spare. **16 bytes was not a choice**: even bit-packed the fields need
56+40+16+24+1+8+1+36 = **182 bits**, well past the 128 a 16-byte entry holds; dropping id_hi
entirely still needs 146.

Also: **generation 8 -> 24 bits** (retirement ceiling 255 -> ~16.7M reuses per slot, threshold
`0xFF` -> `0xFFFFFF`); **PCC/mepcc 32/16 -> 56/40** with `VEDA_PCC_UNBOUNDED` `0xFFFF` ->
`0xFFFFFFFFFF`; **veda_attr 32 -> 64 bits** (`Length[55:16] | Perms[15:0]`, backward-compatible by
construction). All four `INTERIM BRIDGE RTL-3` markers left by RTL-2b are now **gone** -- that
grep-to-zero contract is discharged.

### Two decisions worth naming

- **id_hi widened to 36 bits, deliberately diverging from Sail.** Sail bounds the ODT *index*
  instead (a flat `vector(2^44)` is ~300 TiB and will not compile there) -- that is a modelling
  constraint, not an architectural one. RTL is a 256-entry direct-mapped table with a hi-tag, so it
  mirrors the **property** (no two Object_IDs may alias one slot) at the true 44-bit width rather
  than mirroring Sail's mechanism, for 3 extra bytes in an entry that has 7 spare.
- **Populate stays split**, matching Sail: plain `veda.odt.populate` keeps its packed single-GPR
  descriptor and is now explicitly the **compact** form (Base32/Length16 zero-extended), because
  Base56+Length40+Perms16 = 112 bits cannot fit one register; `veda.odt.populate.fast` is the
  **wide** form. This is worth a great deal to the corpus: every test that hardcodes a packed
  descriptor keeps working untouched.

## What this increment actually cost -- four silent bugs, none caught by the compiler

This is the honest core of the write-up. **Every bug below compiled cleanly and produced wrong
values.** Sail's type checker would have rejected all four as type errors; Verilog accepted them.

1. **Seven missed `>>1` sentinel comparisons.** The previous-cycle forms
   (`>>1$veda_pcc_length != 16'hFFFF`) compared a 40-bit signal against a 16-bit constant. My first
   grep missed them because it filtered on the same line containing "pcc".
2. **Reset-seed slot collision -- my own edit script's bug.** A sequential string replacement moved
   slot 1's Base from `+16` to `+32`, and then the slot-2 pass matched that *output* and moved it
   again to `+64`, so slot 1 clobbered slot 2. Valid syntax, valid addresses, wrong slot.
3. **CSR read/write width slices.** Reads zero-extended from the old widths; writes sliced
   `csr_wdata[31:0]` / `[15:0]` into 56/40-bit registers, silently dropping the upper bits software
   wrote.
4. **The trap-reset arm** `(>>1$veda_trap_taken) ? 16'hFFFF :`. In a 40-bit field that is
   `0x000000FFFF` -- a real 65535-byte bound, **not** the sentinel. So after any trap, PCC stayed
   bounded and the handler itself could not execute. This one broke 28 tests at once, and my grep
   filter could not have found it: **the line contains no "pcc" text at all** (the register name is
   on the mux header line above).

Bug 4 was found by **probing the running simulation**, not by reading or grepping: a throwaway
testbench dumped `trap`, `pcc_viol`, `pc` per cycle and showed `trap=1` firing correctly, the jump
to the handler happening, and then `pcc_viol=1` stuck with the PC frozen at the handler entry. That
is the real lesson of this increment: **in RTL, when reading and grep have both been exhausted, run
the model and look at its signals.**

## Verification

| Stage | Result |
|---|---|
| RTL-3 first run | 16 pass / 42 fail |
| after the seed-collision fix | 30 / 28 |
| after the CSR width fixes | 29 / 28 |
| after the trap-reset sentinel fix | **48 / 9** |
| after the 9 sentinel-cascade test updates | **58 / 0** |

The final 9 were the **sentinel cascade** -- the same one Sail hit (16 tests there). All nine were
diagnosed against the running simulator by parallel agents under a hard rule: *if the failure is
not explained by the sentinel/width change, do not invent a fix -- report a suspected real RTL bug
and leave the file alone.* **Zero suspected RTL bugs** were reported. The fixes are of exactly two
kinds: stale `0xFFFF` constants, and the "max-length code object to return to unbounded" idiom,
which now requires the wide populate path because the compact descriptor's 16-bit Length field
cannot express a 40-bit sentinel. No assertion was relaxed, removed or retargeted -- verified by
reading the diffs, and the full suite was then **re-run independently** rather than trusting the
per-agent reports.

### Mutation testing

- **Mutant W -- revert the ODT stride to 16** while the layout stays 32-byte, so entries overlap
  (slot N's fields land inside slot N-1's). This is the single most dangerous error class in this
  increment, because **the stride does not reference `ODT_ENTRY_BYTES`** -- bumping the localparam
  alone would leave both stride sites at 16 with no diagnostic whatsoever.
  **Result: 58 -> 14 passing; 44 tests failed.**

That number is the point. A one-character omission that no compiler, linter or type checker would
ever report takes down three quarters of the suite -- which is exactly why the stride sites are
called out explicitly in the silent-truncation checklist rather than trusted to the localparam.
The mutation also confirms the corpus genuinely exercises the ODT layout end to end: essentially
every capability test depends on entries landing where the reader expects them.

The pristine RTL was restored and the suite re-verified before committing; no mutant code is
committed.

## Honest scope

- **RTL only.** No Sail change; no ACT4 numbers claimed (that suite is pure GPR datapath).
- The ODT is still **256 entries**, and the modeled namespace is still bounded by that -- what
  changed is that an entry can now *describe* a Linux-scale object, and that two distinct
  Object_IDs can no longer alias one slot at any width.
- `veda_mode` (CSR 0x7C5) remains 32 bits; it is unrelated to the capability format.
- The DESIGN_08 region table (domain-segmented Object_ID + CRBR) is **not** in the RTL yet -- that
  is the increment that closes Phase 1 on the hardware side.
