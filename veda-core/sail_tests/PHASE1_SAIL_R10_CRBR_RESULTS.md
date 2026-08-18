# Sail respec -- R10: the CRBR load/validate/save/restore, closing the compartment escape

**Date:** 2026-08-12. **Layer:** Sail (`veda-core-sail-riscv`, branch `phase1-respec`). **Closes:**
DESIGN_07 finding R10, raised during RTL increment RTL-4. **Baseline:** 72/72. **Result:** 76/76.

## 1. What R10 is

RTL-4 built the DESIGN_08 region table but shipped the Current-Region Base Register (CRBR)
**reset-only**, and recorded why in finding R10: wiring the "obvious" CRBR load at domain entry
*without a matching restore* opens a compartment escape.

> Domain A invokes domain B. The CRBR loads region B. OCReturn carries no saved caller region, so
> the CRBR is never restored -- A resumes with **B as its current region**. And the current region
> is fault-exempt by construction (`veda_region_is_resident` returns true for it without consulting
> the Region Table). A has inherited unchecked, RT-free reach into B's entire object namespace.

This increment implements the fix in Sail, under one rule with two clauses:

> **The CRBR is loaded ONLY from the Object_ID[43:24] of the code capability being entered or
> returned to, and EVERY load is validated through the Region Table -- never through the
> current-region fast-path exemption.**

The first clause makes the source unforgeable: only a residency-gated Bind ever mints a capability
carrying a given Object_ID, so a compartment cannot fabricate a region field. The second makes
`veda_region_is_resident`'s exemption sound **by construction** instead of by convention -- the CRBR
can only ever come to name a region the RT said was resident at load time.

## 2. Where each piece landed

| Piece | Site | What it does |
|---|---|---|
| Load at entry | `veda_cap_insts.sail` OCInvoke, after all 9 capability checks, before the first commit | `veda_crbr_load(cs1.Object_ID[43:24])` |
| Load at return | `veda_cap_insts.sail` OCReturn, after its 4 checks, before commit | same, from the sentry's Object_ID |
| Fault on non-resident | both crossings | `veda_region_rt_resident` false -> `veda_trap(rs1, VEDA_CAUSE_REGION_FAULT)`, commits nothing |
| Trap save + reset | folded into `veda_pcc_save_and_reset` | saves CRBR (if non-root), resets to region 0 |
| mret/sret restore | folded into `veda_pcc_restore_on_xret` | restores saved CRBR, self-consuming |
| Trap chokepoint guard | `handle_trap_extension` | gained a second disjunct (`veda_current_region != 0`) |
| Observability | read-only CSRs `0x7C6`/`0x7C7` | `veda_current_region` / `veda_saved_region` |

## 3. The decisions, and why

### 3.1 Validate RT-direct, never through the fast path

`veda_region_rt_resident` is a **separate** function from `veda_region_is_resident`, deliberately
without the current-region exemption. Using the exempt function for the load would be circular: a
stale current region would validate its own successor. The RT-direct check also gives `rt_valid`
its first-ever consumer -- an unconfigured slot must fail closed even if its `resident` bit is
garbage-true, which is exactly what `vc_r10_rt_valid_gate_neg` pins.

### 3.2 The empty sentinel is an out-of-window region, not zero

mepcc uses `VEDA_PCC_UNBOUNDED` as its "nothing saved" sentinel. The CRBR cannot: **region 0 is a
legitimate region** (the root domain every pre-DESIGN_08 test runs in), so "saved == 0" cannot mean
"nothing saved." The saved-region sentinel is `VEDA_REGION_NONE = 0xFFFFF`, an out-of-window value
(`>= VEDA_REGION_MODELED`) that can never be a real current region because every load is
RT-validated and out-of-window regions are never resident.

### 3.3 The two disciplines stay independent

The CRBR restore rides the same `mret` as the mepcc restore but under its **own** guard, not nested
inside mepcc's. Their capture conditions differ -- mepcc captures when PCC was bounded, CRBR
captures when the region was non-root -- and OCInvoke into a max-length (unbounded) code object
whose Object_ID names a non-zero region produces exactly the state where they disagree: PCC
unbounded, CRBR non-zero. Coupling the restores would strand a saved region in that case. The trap
chokepoint guard `handle_trap_extension` gained the matching second disjunct for the same reason.

### 3.4 The restore is infallible -- and that is checked, not assumed

`mret` cannot raise a trap in this model (verified by reading the dispatch: `veda_trap`'s result is
discarded in a unit context, and `handle_exception` from inside the hook would clobber `mepc` and
then be overwritten by `mret`'s own `set_next_pc` -- a livelock). So the CRBR restore re-installs
the saved pair verbatim with no RT re-validation. That is sound **today** because the Region Table
is immutable after reset (no RT-write instruction exists). It carries a **hard obligation**, written
into the code and DESIGN_07, for the future RT-write instruction: it must refuse to clear residency
on the current region and on any saved region, or this restore stops being sound the day it lands.

### 3.5 Observability is read-only, and that closes rather than opens a surface

The whole reason R10 was a *silent* escape is that nothing ever observed the CRBR. Exposing it
read-only (CSRs `0x7C6`/`0x7C7`) is the honest fix for that gap and is what lets a test assert the
save/reset/restore cycle directly. They are **strictly read-only** -- accessibility is granted only
for `CSRRead`, so any write attempt is `Illegal_Instruction` before dispatch and no `write_CSR`
clause exists. A *writable* CRBR CSR would be a Milestone-19/20-class self-escape (a live compartment
CSRRW-ing its own ODT base re-points its whole namespace); read-only adds no such surface and matches
the model's established "capability metadata is always inspectable" principle.

## 4. Verification

**76/76** (72 baseline + 4 new). The 72 baseline pass unchanged, which is the load-bearing
compatibility result: every existing invoke/return uses a region-0 code capability, so every CRBR
load in the old corpus resolves region 0 -- and region 0 is RT-resident-seeded, so the strictly
RT-validated (no fast-path) load passes for all of them. If region 0 were not seeded resident, all
26 invoke/return tests would fault; they do not.

### The four new tests -- the entire coverage of the new mechanism

1. **`vc_r10_ocinvoke_region_fault_neg`** -- OCInvoke into non-resident region 2 raises
   `REGION_FAULT` (0x09, mtval `0x149`) and commits nothing; a region-0 bind in the handler still
   works, proving the CRBR did not move.
2. **`vc_r10_ocreturn_region_fault_neg`** -- the return half: OCReturn through a region-2 sentry
   faults (mtval `0x1A9`). This is the sharp end of the escape closure -- the original hole was
   precisely that return restored no region.
3. **`vc_r10_rt_valid_gate_neg`** -- OCReturn through a region-3 sentry, where RT[3] is the
   contradictory `{rt_valid=false, resident=true}`, faults **because** `rt_valid` is false -- the
   fail-closed conjunct's only witness.
4. **`vc_r10_crbr_invoke_trap_return`** -- the positive round-trip, reading the CRBR through the new
   CSR at every step: 0 before entry, **1** inside the region-1 compartment, **0** in the trap
   handler (reset) with **1** in the saved shadow, **1** again after `mret` (restored) with the
   shadow self-consumed back to `0xFFFFF`, and **0** after the return to the unbounded root.

### Mutation testing

Six mutants, each reverting exactly one R10 decision. Every pattern is asserted to apply exactly
once before the model is rebuilt -- a silently-unapplied mutation would report the corpus still
green and be misread as "the test is vacuous," the worst possible false negative here.

| Mutant | What it reverts | Result | Test that fell |
|---|---|---|---|
| **M1** | the OCInvoke region gate | 75/76 -- KILLED | `ocinvoke_region_fault_neg` |
| **M2** | the OCReturn region gate | 74/76 -- KILLED | `ocreturn_region_fault_neg` + `rt_valid_gate_neg` |
| **M3** | the `rt_valid` conjunct (fail-closed) | 75/76 -- KILLED | `rt_valid_gate_neg` |
| **M4** | the trap-entry reset to region 0 | 75/76 -- KILLED | `crbr_invoke_trap_return` |
| **M5** | the `mret` restore | 75/76 -- KILLED | `crbr_invoke_trap_return` |
| **M6** | the self-consume on restore | 75/76 -- KILLED | `crbr_invoke_trap_return` |

**Six for six.** Every decision in Section 3 is load-bearing, and every new test discriminates.

Three of these deserve individual mention:

- **M2 kills two tests, and that is correct rather than sloppy.** Both `ocreturn_region_fault_neg`
  and `rt_valid_gate_neg` exercise OCReturn, so removing that one gate drops both. The arithmetic
  is a consistency check on the sweep itself.
- **M3 is the surgical one.** Dropping `rt_valid` and keeping `region_resident` kills exactly one
  test -- the only one that can see it, because RT[3] is the only slot seeded into the
  contradictory `{valid=false, resident=true}` state. Without that fixture the conjunct would have
  been an unobserved line of code, indistinguishable from redundancy.
- **M4, M5 and M6 all kill the same test**, which is the point of building one positive round-trip
  that reads the CRBR at every step rather than three narrow ones: trap-reset, `mret`-restore and
  self-consume are three separate failures of a single mechanism, and the test observes all three
  transitions through CSR `0x7C6`/`0x7C7`.

#### A harness gap this sweep exposed, fixed rather than worked around

The first sweep attempt **hung** on M5 and burned its wall-clock budget. The cause is worth
recording, because it is a property of the test harness, not of the fix:
`run_veda_selfcheck_tests.sh` invokes `sail_riscv_sim` with **no instruction bound**, so a test
that livelocks stalls the entire suite indefinitely rather than failing.

Under M5 (no CRBR restore on `mret`) the positive round-trip test does not halt cleanly. It reads
the CRBR, sees the wrong region, and branches to `fail:` -- but `fail:` lies **outside** the
compartment's PCC bound, so the jump faults on fetch, the handler `mret`s back into the compartment
(restoring PCC via mepcc), and the sequence repeats forever. The test is genuinely not passing, but
it expresses that by spinning instead of halting.

Fixed deterministically with `--inst-limit 2000000` on every test, which converts the livelock into
a clean, reproducible FAIL. An instruction bound is preferable to a wall-clock `timeout` here
because it is machine-independent and repeatable. Verified not to disturb anything else: the whole
corpus still runs green under the bound (no legitimate test comes near two million instructions).
**Recommendation carried forward:** the committed runner should adopt the same bound, so no future
livelocking test can ever hang CI.

## 5. Honest scope

- **Sail only.** The RTL still ships the CRBR reset-only; the RTL mirror of this fix is the next
  increment (RTL-5). No RTL or ACT4 numbers are claimed here.
- **OCJALR is out of scope**, matching the fix's stated boundary (OCInvoke/OCReturn only). OCJALR
  deliberately does not narrow PCC or cross a compartment boundary, so it loads no CRBR; a
  sealed-pair OCJALR inherits the caller's region. Recorded, not changed.
- **No RT-write instruction exists**, so the trap-save/reset and the infallible restore are, in the
  current model, forward-looking hardening whose behavioural effect is not independently observable
  (a resident region stays resident, so the fast-path and RT-direct answers coincide). The positive
  test proves the save/restore round-trips without corruption via the observability CSR; the
  *security value* of the reset lands only once a handler can page a region out, which the recorded
  RT-write obligation covers.
- **Multi-hart is untouched.** The single-hart answer ("hardware refuses to clear residency on the
  current/saved region") does not generalize to "one hart evicts a region another hart's CRBR
  names" -- that stays on the Phase 6 checklist.


---

## Amendment, R60 (D5): `mret` is not the only consumer

This document's Section 3.2 and the M6 mutant both describe the shadow as **self-consuming on the
xret restore**, which is what R10 shipped and what this suite measured. It was incomplete, and the
gap was a real bug -- recorded as **DESIGN_07 R60 (D5)**.

`veda_trap_frame_abandon`, which **OCRETURN** calls, released the depth, the mepcc triple and the
poison, and **not** the saved region. Since `veda_crbr_restore_on_xret` fires on the sentinel alone
-- no depth term, deliberately outside the mepcc guard -- a handler entered from a region-1
compartment and left by OCRETURN stranded `saved_region = 1`, and **the next `mret` the machine
executed, by unrelated region-0 code for an unrelated reason, installed region 1.** Measured by
instruction trace on the unfixed model.

OCRETURN now also calls `veda_crbr_release()`, unconditionally, immediately after `veda_crbr_load`
-- the region has just been installed from `cs1`, so a saved one is superseded by definition. New
test: `vc_d5_crbr_shadow_leak.S`, built from `vc_r10_crbr_invoke_trap_return.S` with exactly one
change -- the handler leaves by OCRETURN instead of `mret`.

**The lesson for this document's own mutation census:** M6 killed the self-consume on the `mret`
path and proved that path is checked. It could not see that a second consumer was missing entirely,
because a mutation census can only mutate code that exists.
