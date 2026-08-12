# RTL mirror -- Increment RTL-4: DESIGN_08 region table, CRBR, REGION_FAULT

**Date:** 2026-08-12. **Layer:** RTL (`veda_core.tlv`). **Branch:** `sindhu`. **Mirrors:** the
Sail DESIGN_08 experiment, commit `1fef6e3d` (`PHASE1_SAIL_DESIGN08_REGION_EXPERIMENT_RESULTS.md`).

This is the increment that closes Phase 1 on the hardware side.

## 1. What changed

The 44-bit Object_ID is no longer one flat name. It is **two fields**:

```
Object_ID[43:24] = region  (20 bits)  -- the protection domain
Object_ID[23:0]  = local   (24 bits)  -- the object's name inside that domain
```

An ODT entry address is now resolved in two steps instead of one:

| | before RTL-4 | after RTL-4 |
|---|---|---|
| index | `Object_ID[7:0]` | `region_base(region) + local[7:0]` |
| where the base comes from | nowhere -- there was one table | the **CRBR** if intra-domain, the **Region Table** otherwise |
| a domain that is paged out | could not be expressed | **`VEDA_CAUSE_REGION_FAULT` (0x09)**, an explicit trap |

New state: a flat, always-resident **Region Table** of `RT_ENTRIES = 8` entries
(`rt_valid` / `rt_resident` / `rt_odt_base` / `rt_backing` / `rt_generation`, mirroring Sail's
`region_entry`), and the **CRBR** (`$veda_current_region` + `$veda_current_odt_base`).

`ODT_ENTRIES` grew 256 -> 768: three windows of `ODT_REGION_ENTRIES = 256`. Region 0 -> entry 0
(resident), region 1 -> entry 256 (resident), region 2 -> entry 512 (**non-resident**).

## 2. The decisions, and why

### 2.1 Grow the table; do not shrink the per-region index

The tempting move is to hold the ODT at 256 entries and split it into windows of 128 or 32. That
would have been a **security regression with zero test signal**, and the evidence is specific
rather than theoretical. The corpus really contains the pairs
`(2,130) (3,131) (5,133) (6,134) (72,200) (73,201) (82,210)`. At a 128-entry window the index
narrows to `local[6:0]`, which leaves bit [7] checked by neither the index nor the `id_hi` tag --
so a Bind of Object_ID 2 would silently return Object_ID 130's descriptor. **No test binds both
members of any pair, so the whole suite would still have reported PASS.**

At a 32-entry window it is worse in a quieter way: the tag would have to widen to `[43:5]`, and the
three reset seeds never write the `id_hi` bytes (they rely on the array pre-zero). `60 >> 5 = 1`,
not 0, so the Object_ID-60 seed would read as not-found and break `m12`/`m12_neg` while looking
like an unrelated failure.

`odt_mem[]` is a simulation byte array, not silicon. 8 KiB -> 24 KiB costs no area, no timing, and
no memory map (`elfmem` ends `0x8007_FFFF`, TCM scratch starts `0xA000_0000`). Sail made exactly
this call and said so (`veda_regs.sail:459-462`): it sized the table to R x (unchanged window)
rather than shrinking the window to fit a fixed table.

### 2.2 Three windows, not two -- so the fault test can fail loudly

A non-resident region provably never reaches the array, so on pure architectural grounds region 2
needs no storage. It gets a window anyway, because it makes the REGION_FAULT test **strictly
sharper**. With region 2's object genuinely seeded and valid, a missing residency gate makes the
bind **succeed** -- an unmistakable failure. Without the seed, a missing gate would still trap,
with cause 0x05, and a test that only asserted "it trapped" would pass straight over the hole.
The fixture is chosen so the failure mode is loud, not so the table is minimal.

### 2.3 The `id_hi` tag stays at 36 bits -- and that is a proof, not an omission

Two Object_IDs alias iff `entry(A) == entry(B)`, where
`entry(X) = region_base(region(X)) + local(X)[7:0]`. Every `region_base` is a multiple of 256 and
`local[7:0]` is in `[0,256)`, so the base is exactly the window number x 256 and `local[7:0]` is
exactly the offset within it. Therefore two entries collide iff they land in the same window **and**
agree on bits `[7:0]` -- which means two *different* Object_IDs that collide must differ somewhere
in `[43:8]`, which is precisely what the tag covers. Index bits and tag bits stay exactly
complementary and jointly total over all 44 bits.

This still holds in the pathological case DESIGN_08 warns about: if two distinct regions were
**mis-programmed to the same base**, they would land in the same window -- but `region` lives in
`[43:24]`, inside `[43:8]`, so the tag differs and the lookup reads not-found. The 36-bit tag is
the **only backstop in the design against RT mis-programming**, which is the reason to keep it at
full width rather than narrowing it to a local-only `[23:8]`.

### 2.4 The region fault is a hard trap for **all three** bind modes

This knowingly narrows this file's own longstanding "Rebind never hard-traps for ANY reason"
invariant -- the first condition ever to do so. The reason is not symmetry, it is availability: a
paged-out domain is a **recoverable, serviceable** event. If Bind-NoTrap merely soft-failed with a
cleared Tag, and Rebind merely cleared Tag, the caller would be told *"your object is gone"* instead
of *"your object's domain is paged out, service it and retry"* -- the pager would never be invoked
and a perfectly live object would look permanently destroyed. Sail states this explicitly
(`veda_bind_insts.sail:145-147`).

### 2.5 Cause ordering: 0x09 must beat 0x05

A non-resident region also produces `!$veda_odt_valid`, so for a plain Bind the object-not-found
violation fires in the *same cycle*. If 0x05 won the priority chain, a domain that is merely paged
out would be reported as "the object never existed" -- destroying exactly the distinction 0x09 was
introduced to make. This is not a style preference; it is the difference between a handler that
pages the domain in and one that gives up. Mutant M4 exists solely to prove the ordering holds.

### 2.6 Mutation W's hazard removed at the source

The `* 32'd32` stride literal was Mutation W's entire hazard in RTL-3: it did **not** reference
`ODT_ENTRY_BYTES`, so bumping the localparam while the stride stayed at 16 took the suite from 58
passing to 14 with no compile diagnostic anywhere. Both address computations now reference the
parameter. That removes the hazard rather than relying on a checklist to remember it.

## 3. The refusal -- finding R10, and why the CRBR is deliberately inert

**The CRBR is implemented and reset-only. No OCInvoke load, no OCReturn load, no CSR.** This is a
refusal, not an omission, and it is the most important decision in this increment.

DESIGN_08 Section 4 says the CRBR is "set explicitly at domain entry" and stops there. Sail writes
`veda_current_region`/`veda_current_odt_base` in exactly one place -- its reset seed
(`veda_regs.sail:569-570`) -- and has no OCInvoke arm at all. So wiring a load at OCInvoke here
would be new, formally unverified behaviour. That alone would be reason to hold it.

But it is worse than unverified. **Landing the obvious feature would open a compartment escape.**

> A caller in domain A invokes a callee in domain B. OCInvoke loads the CRBR with B. OCReturn's
> only operand is a sentry capability, and no saved-caller-region state exists anywhere -- so the
> CRBR is never restored. The caller resumes with **B as its current region**. And the current
> region is **fault-exempt by construction** (`veda_region_is_resident` returns true for it without
> consulting the RT at all). The caller has therefore inherited unchecked, Region-Table-free access
> to the callee's entire object namespace, and retains it indefinitely.

That is a confused-deputy escape, not a performance bug. It is created *by* adding the feature
carelessly, which is why the secure move is to not add it yet.

### 3.1 The fix, designed here: derive the region from the capability being entered

The fix needs **no new save register**, because the information is already present and already
unforgeable. Both crossings operate on a capability, and a capability carries its own Object_ID:

- **OCInvoke** enters a sealed code capability. Its Object_ID's region field *is* the entered
  domain.
- **OCReturn** consumes a sentry capability (otype `0xFFFE`) naming the caller's code object. Its
  Object_ID's region field *is* the caller's domain.

Both are reached through the same signal the RTL already has (`$veda_rs1cap_object_id`), and the
`$veda_pcc_base` mux already has arms in exactly the right shape for both crossings. So the rule is:

> **The CRBR is loaded only from the Object_ID of the code capability being entered or returned to,
> and every CRBR load is validated through the Region Table -- never through the fast path.**

That last clause is what makes "the current region is always resident" true *by construction*
rather than by convention: a CRBR can only ever come to name a region the RT said was resident.
Trap entry and `mret` need the symmetric treatment (a save/restore pair mirroring `mepcc`,
including the conditional-capture and self-consuming discipline that a real nested-trap bug already
forced on `mepcc` in this file).

**This belongs in Sail first**, as every prior increment has. It is written down here as **R10**
rather than implemented, and the RTL is structured so the arms have one obvious place to land.

Holding the CRBR inert costs no coverage: pinned at region 0 / base 0, region-0 binds exercise the
fast path, region-1 binds exercise the RT read path, and region-2 binds exercise REGION_FAULT.

## 4. Verification

| Stage | Result |
|---|---|
| Baseline before any edit | **58 / 0** |
| After the full RTL-4 mechanism, before adding any new test | **58 / 0** -- bit-for-bit, zero regression |
| With the four new region tests | **62 / 0** |

The zero-regression claim was **demonstrated, not assumed**: the baseline was captured and re-run
before the new tests existed, precisely because "we added tests and it is still green" proves
nothing about the old ones.

Region 0's arithmetic is unchanged by construction -- base 0 + `local[7:0]` is byte-for-byte the
pre-RTL-4 formula -- and all 88 corpus Object_IDs are region 0 (the largest is 99999, well under
2^24). `m15_neg`'s deliberate `{32, 288}` alias still collides on entry 32 and is still
distinguished by the tag; the `m24` cycle-count tests are unaffected because the rewritten TCM
predicate is provably identical for every region-0 ID.

### 4.1 The four new tests

They are the **entire** coverage of the new mechanism -- no pre-existing test can reach the RT read
path, the CRBR resolution, or cause 0x09, because the whole corpus is region 0. A green suite after
this change proves only that the region-0 fast path was not broken.

1. **`region_unique`** -- `{region=0,local=1}` (Base `0x80010000`) and `{region=1,local=1}`
   (Base `0x80020000`) are different objects. Then it **dereferences** the region-1 capability,
   which is the only way to catch the Bind path and the re-check path drifting apart.
2. **`region_fastpath`** -- probes the RT read enable and counts it. Three intra-domain binds:
   **exactly 0** RT reads. One cross-domain bind: **exactly 1**. The exactness on both sides is the
   point -- it proves a count that depends on *which domain*, never on access history, which is what
   distinguishes a single architectural register from a cache.
3. **`region_fault_neg`** -- an in-window non-resident domain and an out-of-window domain both raise
   0x09 with the full `mtval` word checked (`0x69`, `0x89`), and the faulting Bind claims no ODT
   ownership.
4. **`region_fault_modes_neg`** -- all three bind modes hard-trap, each with its destination
   capability **preloaded with a real bound capability first** so "untouched" is genuinely
   observable. Without the preload, a suppressed write and a Tag-clear on an already-zero register
   are indistinguishable and the test would pass either way.

### 4.2 Mutation testing

All four tests passed on the first run, which is exactly when a test suite most deserves to be
distrusted. Six mutants, each reverting one specific decision:

| Mutant | What it reverts | Result |
|---|---|---|
| **M1** | Bind path ignores the region base | 60 / **2** -- KILLED |
| **M2** | **only** the dereference re-check ignores the base | 61 / **1** -- KILLED |
| **M3** | region fault gated on plain Bind only | 61 / **1** -- KILLED |
| **M4** | 0x09 moved after the bind-trap arm (reports 0x05) | 61 / **1** -- KILLED |
| **M5** | Rebind still writes rd on a region fault | 61 / **1** -- KILLED |
| **M6** | a faulting Bind still claims ODT ownership | 61 / **1** -- KILLED |

**Six for six.** Every decision in Section 2 is load-bearing, and every new test discriminates.

Two of these are worth naming individually:

- **M2 is the one no amount of care would have caught by reading.** It region-ifies Bind but leaves
  the dereference re-check -- a separate, hand-written copy of the same address computation ~700
  lines away -- resolving against region 0. The entire pre-existing 58-test corpus stays green,
  because region 0's base is 0 and the two formulas are identical there. It is killed only because
  `region_unique` **dereferences** its region-1 capability instead of merely binding it.
- **M6 mutates state that no capability register shows.** A region-faulting Bind still writes
  `MHARTID` into the ODT's owner byte -- a trapping instruction silently taking ownership of an
  object in a domain it was just refused. That write lives in the trailing raw `\SV always_ff`
  behind `BOGUS_USE`, invisible to TLV-level review, and is caught only because the testbench probes
  `odt_mem[]` directly.

The mutation harness asserted that each pattern applied **exactly once** before running, and aborted
otherwise. A mutation that silently fails to apply reports the suite still passing and reads as
"the test is vacuous" -- the worst possible false negative in this exercise. The pristine file was
restored and byte-diffed against a backup afterwards; no mutant code is committed.

## 5. Knowing divergences from Sail

Recorded rather than smoothed over:

- **RTL bounds the resolved ENTRY index; Sail bounds the LOCAL field.** Sail rejects
  `local >= 2^20`; the RTL confines by truncation to `local[7:0]` and distinguishes by the `id_hi`
  tag. Both discharge the same global-uniqueness obligation by different means. The divergence is
  permanent unless one side moves -- Sail's `odt_entry` has no `id_hi` field to consult.
- **Sail region-faults on bind mode 11; the RTL has no mode-11 decode at all.** Sail's gate precedes
  its `VEDA_BIND_RESERVED => Illegal_Instruction()` arm.
- **The RT is reset-seeded with no population instruction.** There is no analogue of ODT-Populate
  and no authority gate for it. Honest for this increment, but a real limitation: DESIGN_08 and
  `veda_types.sail:313-317` both flag that a stale or corrupt `region_odt_base` has **region-wide**
  blast radius, strictly larger than any single ODT entry's -- so the RT's write authority is itself
  a first-class security surface. An RT-Populate instruction with an ODA-style authority gate is
  probably the next increment's main content.
- **The CRBR is reset-only in both models**, so the domain-entry load remains prose-only in Sail and
  RTL alike. **No Sail parity is claimed for it.** The residency gate and cause 0x09 are
  Sail-verified; the load is not.

## 6. Honest scope

- **RTL only.** No Sail change this increment; no ACT4 numbers claimed (that suite is pure GPR
  datapath).
- The modeled namespace is still bounded by the table: 3 windows x 256 entries, 8 RT entries. What
  changed is that the namespace now has **structure** -- a domain axis that is bounded, flat and
  resident, and an object axis that is not.
- **The cross-region RT read's latency is not charged.** `DRAM_EXTRA_CYCLES` is committed at 0, and
  wiring the read into the stall path carries a real trap-redirect-delay hazard (the PC's freeze on
  `>>1$veda_dram_busy` outranks `>>1$pc_src`, so a region-faulting bind would delay its own trap).
  The one-read property is proved **structurally** by the read-enable counter instead of temporally.
  DESIGN_08's cost claim is therefore demonstrated in shape, not in cycles.
- **The CRBR load is not implemented** -- see R10 above. This is the single largest thing DESIGN_08
  describes that this increment does not deliver, and it is deferred deliberately.
- Multi-hart is untouched. R10's fix is stated for a single hart; a real multi-hart core must also
  answer what happens when one hart evicts a region another hart's CRBR names.
