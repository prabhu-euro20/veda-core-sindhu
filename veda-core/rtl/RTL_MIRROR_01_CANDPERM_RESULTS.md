# RTL mirror -- Increment 1: CAndPerm (rights attenuation)

**Date:** 2026-08-11. **Layer:** RTL (TL-Verilog `veda_core.tlv`). **Branch:** `sindhu` (a fresh
clone of the Veda-Core repo; the frozen `rva23-core` tree is never modified). **Mirrors:** the
Sail-verified `Veda-Core-sail-riscv` CAndPerm increment and `veda-core-linux`
`design/DESIGN_01` (New instruction -- CAndPerm).

This is the first increment of porting the Sail-verified Phase 1 respec into hardware. It starts
with CAndPerm for the same reason the Sail side did: it is purely additive (one new funct7, no
change to any existing instruction), so it de-risks the whole RTL build/test/mutation loop in
this environment before the much larger 256-bit-format change.

## The environment gate (established first, honestly)

Before any edit, the RTL toolchain was proven to actually work here and a **green baseline was
established**: SandPiper (the TL-Verilog to SystemVerilog cloud transpiler) transpiles, Icarus
Verilog compiles and simulates, and the committed smoke suite runs **53/53 TEST PASSED** on the
unmodified RTL. The one real setup detail found and fixed: the smoke runner expects pre-built
`.hex` test images (gitignored artifacts) and does not build them, and the `.S` sources use `//`
comments, so they must be assembled with `riscv64-unknown-elf-gcc` (which preprocesses) rather
than raw `as`. Without a real green baseline, no "mirror verified" claim would be honest.

## What was built

`veda_core.tlv`, Custom-2 (`0x5b`), funct3 `001`, **funct7 `0010111`** -- the next free slot
(OCA `0001010` .. OCRETURN `0010110`), matching the Sail encoding exactly. Nine edits, all in the
manipulate-family idiom the RTL already uses for OCA/CSetBounds/CSeal:

- decode `$is_veda_candperm`; write-enable `$candperm_wr_en`;
- the `$base`, `$length`, `$offset`, `$otype` field muxes carry through from cs1 unchanged;
- the `$perms` mux is the one computed field: `cs1.Perms & rs2[15:0]`;
- the `$tag` mux takes `$veda_candperm_ok = cs1.Tag && (cs1.otype == 0xFFFF)` -- Tag survives only
  a tagged, unsealed source. **No bounds term** (masking permissions cannot leave the window), so
  monotonicity is structural: bitwise AND can only clear.

## Verification

| Stage | Result |
|---|---|
| Baseline (unmodified RTL) | **53/53 TEST PASSED** |
| With CAndPerm (transpile + smoke) | **53/53 TEST PASSED, zero regressions** |
| CAndPerm positive test | **PASS** |
| CAndPerm negative test | **PASS** |

Zero-regression alone would not prove CAndPerm *works* (a never-exercised no-op also passes 53/53),
so two behavior tests were written and run:

- `veda_smoke_candperm.S` / `tb_veda_smoke_candperm.sv` -- binds Object_ID 1 (Perms 0x100C),
  attenuates with mask 0x000C (result 0x000C), checks Base and Tag are untouched, and checks that
  masking **everything** away still leaves the capability Tag=1 (weaker, not destroyed). Observed:
  `orig=0x100c masked=0xc masked_tag=1 base=0x80010000 clear=0x0 clear_tag=1` -- PASS.
- `veda_smoke_candperm_neg.S` / `tb_veda_smoke_candperm_neg.sv` -- mints a seal-authority object at
  runtime (Object_ID 10, mirroring veda_smoke_m6.S, since the RTL reset-seed -- unlike Sail's --
  provides no seal-permission object), seals c1, then attenuates the **sealed** c1 and checks the
  result's Tag is 0. Observed: `sealed_tag=1 sealed_otype=0x0 attenuated_tag=0` -- PASS.

### Mutation testing

- **Mutant -- drop the mask** (`$perms = cs1.Perms`, dropping `& rs2`). Expected: the positive
  test fails, the negative one does not. **Result: candperm FAILED, candperm_neg PASSED** -- the
  positive test genuinely exercises the AND, and the mutation is precise (the negative test checks
  the seal-Tag path, which the mask does not touch). The pristine RTL was restored and both tests
  re-verified PASS before committing; no mutant code is committed.

## Honest scope

- **RTL only for this increment.** The RTL is still the pre-respec 128-bit-capability core (Base
  32, Length 16, generation 8, 256-entry ODT). CAndPerm's `Perms` field is 16 bits in both the
  current and the respec'd format, so this increment needs no rework when the 256-bit format lands.
- One real difference from Sail recorded here, not hidden: the RTL reset seed provides only three
  objects and no seal-permission one, so the negative test mints its authority at runtime rather
  than relying on a seed (as the Sail test could). The property proven is identical.
- Next increments mirror the Sail order: the 256-bit format, then ODT/populate/PCC widen, then
  generation widen, then the DESIGN_08 region table -- each a much larger RTL change than this one.
