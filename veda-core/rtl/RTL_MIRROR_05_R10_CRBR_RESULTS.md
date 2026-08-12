# RTL mirror -- Increment RTL-5: the R10 CRBR fix (load, validate, save, restore)

**Date:** 2026-08-12. **Layer:** RTL (`veda_core.tlv`). **Branch:** `sindhu`. **Mirrors:** the
Sail-verified R10 fix, fork commit `2fd7070c` (`PHASE1_SAIL_R10_CRBR_RESULTS.md`).
**Baseline:** 62/62. **Result:** 64/64.

## 1. What this closes

RTL-4 built the DESIGN_08 region table but shipped the Current-Region Base Register **reset-only**,
and recorded why as finding R10: wiring the "obvious" CRBR load at domain entry, without a matching
restore, *creates* a compartment escape.

> Domain A invokes domain B; the CRBR loads region B. OCReturn carries no saved caller region, so
> the CRBR is never restored -- A resumes with **B as its current region**. The current region is
> fault-exempt by construction, so A has inherited unchecked, Region-Table-free reach into B's
> entire object namespace, indefinitely.

Sail closed it first. This mirrors that work into hardware, under the same rule:

> **The CRBR is loaded ONLY from Object_ID[43:24] of the code capability being entered or returned
> to, and EVERY load is validated through the Region Table -- never through the current-region
> fast-path exemption.**

## 2. Where each piece landed

| Piece | Signal / site | Behaviour |
|---|---|---|
| RT-direct validation | `$veda_crossing_rt_resident` | `in_window && rt_valid && rt_resident`, **no** intra-region arm |
| OCInvoke gate | last term of `$veda_ocinvoke_violation` | non-resident target -> nothing commits |
| OCReturn gate | last term of `$veda_ocreturn_violation` | same, from the sentry's Object_ID |
| Cause 0x09 | explicit arms in both cause muxes | ahead of each mux's `5'h11` fall-through |
| cap_idx | explicit arm in `$veda_ocinvoke_cap_idx` | reports cs1, not the chain's cs2 default |
| CRBR load | `$veda_current_region` / `_odt_base` | region from the capability, base from the RT |
| Trap save + reset | same muxes + `$veda_saved_region*` | conditional capture, unconditional reset to region 0 |
| mret restore | same muxes | self-consuming, own sentinel guard |
| Observability | read-only CSRs `0x7C6` / `0x7C7` | no write arm exists anywhere |

## 3. The decisions, and why

### 3.1 A separate signal, not the existing `$veda_region_resident`

The Bind-side gate begins `$veda_intra_region ? 1'b1 : ...` -- the fast-path exemption. A CRBR load
must not consult it, for **two** independent reasons:

1. **Circularity.** The exemption's soundness is exactly what a validated load *establishes*. A load
   that consulted it would let a stale current region validate its own successor -- which is the R10
   escape itself.
2. **Wrong operand.** `$veda_region_resident` is keyed off `$veda_region`, which comes from
   `$rs1_data` -- the **GPR** Bind operand. A domain crossing must take its region from the
   **capability**. That is R10's unforgeability clause: only a residency-gated Bind ever mints an
   Object_ID, so a GPR cannot name a domain.

This second point is the sharpest silent hazard in the whole increment. `$veda_object_id` and
`$veda_rs1cap_object_id` are both 44 bits, and **both read region 0 on the entire corpus** -- so
wiring the load to the wrong one compiles clean, passes 64/64, and is architecturally wrong.

### 3.2 Explicit cause and cap_idx arms, not the fall-through

`$veda_ocinvoke_cause`'s default arm is `5'h11` and `$veda_ocinvoke_cap_idx`'s default is **cs2**.
Folding the region fault into the violation term without naming both explicitly would report
`PERMIT_EXECUTE_VIOLATION` against the *data* operand -- a wrong, misleading cause that no
pre-existing test could catch, since the corpus never crosses into a non-resident domain.

### 3.3 The sentinel is `20'hFFFFF`, not zero

Region 0 is a **legitimate** domain (the root every existing test runs in), so zero cannot double as
"nothing saved" the way `VEDA_PCC_UNBOUNDED` does for mepcc. `0xFFFFF` is out-of-window, so it can
never be a real current region -- every load is RT-validated and out-of-window regions are never
resident. Resetting the shadow to `20'b0` instead would make "nothing saved" indistinguishable from
"region 0 saved": the restore would fire on every mret, reinstall region 0 over region 0, and look
perfectly correct forever on this corpus.

### 3.4 The width divergence from Sail is deliberate

Sail's `veda_current_odt_base` is `bits(56)`; the RTL's is **32**, because it holds an ENTRY INDEX
matching `rt_odt_base[31:0]`, not a byte address. Widening it "to match Sail", or storing a byte
address, would shift every non-zero-region base by 32x -- invisible on region 0, whose base is 0.
That is precisely the silent-truncation class that cost RTL-3 four bugs.

## 4. Verification

| Stage | Result |
|---|---|
| Baseline before any edit | **62 / 0** |
| Full R10 mechanism, before adding any new test | **62 / 0** -- bit-for-bit, zero regression |
| With the two new R10 tests | **64 / 0** |

Zero regression was **demonstrated, not assumed**: the mechanism was run against the untouched
corpus before either new test existed. It holds for a checkable reason -- every code capability used
in every crossing in all 62 tests has `Object_ID[43:24] == 0`, and region 0 is seeded
`rt_valid && rt_resident` with `rt_odt_base[0] == 0`, so a strictly validated load writes the CRBR's
own reset value.

### 4.1 The two new tests, and why the suite needed them

That same fact is the danger: **the entire corpus is region 0, so a green run proves nothing about
R10.** All three halves -- load, save-and-reset, restore -- are unexercised by every pre-existing
test. A fully green 64/64 would be equally consistent with the CRBR arms wired to constants.

1. **`r10_crbr_roundtrip`** (positive) -- crosses into **resident region 1** and reads the CRBR
   through the new CSR at every step: `0` before entry, **`1`** inside the compartment, **`0`** in
   the trap handler with **`1`** in the saved shadow, **`1`** again after `mret` with the shadow
   self-consumed to `0xFFFFF`, and `0` after the return crossing. This is the only test in the suite
   that moves the CRBR at all.
2. **`r10_crossing_fault_neg`** (negative) -- both crossings into a non-resident domain raise `0x09`
   (`mtval` `0x189` and `0x1C9`, full word checked) and commit nothing. The two phases deliberately
   name **different regions**, to test the two conjuncts separately:
   - region 2 = `{rt_valid 1, resident 0}` -> fails on the **resident** bit;
   - region 3 = `{rt_valid 0, resident 1}` -> fails on **rt_valid** despite residency saying yes.

   The region-3 arm is the only witness for the fail-closed conjunct: `rt_valid` is otherwise
   write-only in this file, so dropping it from the check would be invisible without that fixture.

The region-2/3 capabilities are **reset-seeded into c12/c13/c14**, mirroring Sail's CRF seeds,
because such a capability genuinely cannot be built at runtime -- Bind is residency-gated and every
derivation instruction carries Object_ID through unchanged. That is the mechanism working, not a
test inconvenience; the seeds model the legal state of a capability minted while the region was
resident and still held across its page-out. c12/c13/c14 were chosen after grep-verifying that every
read of them in the corpus is preceded by a write.

### 4.2 Mutation testing

Eight mutants, each reverting exactly one R10 decision. Every pattern is asserted to apply exactly
once before the model is re-transpiled.

| Mutant | What it reverts | Result | Test that fell |
|---|---|---|---|
| **M1** | the OCInvoke region gate | 63/64 -- KILLED | crossing fault |
| **M2** | the OCReturn region gate | 63/64 -- KILLED | crossing fault |
| **M3** | RT-direct validation (uses the exempt signal) | 64/64 -- **SURVIVED** | -- |
| **M4** | the `rt_valid` fail-closed conjunct | 63/64 -- KILLED | crossing fault |
| **M5** | the CRBR load at OCInvoke | 63/64 -- KILLED | CRBR round-trip |
| **M6** | the trap-entry reset to region 0 | 63/64 -- KILLED | CRBR round-trip |
| **M7** | the `mret` restore | 63/64 -- KILLED | CRBR round-trip |
| **M8** | the out-of-window empty sentinel | 63/64 -- KILLED | crossing fault |

**Seven killed, one survived by design.** Every kill landed on the *intended* test -- the negative
test catches the four gate/sentinel decisions, the positive round-trip catches the three
load/save/restore decisions. That per-test attribution is what makes the result evidence rather
than arithmetic.

Two of these only became killable because the fixtures were changed *while writing the sweep*, after
noticing they would otherwise pass silently:

- **M4** needed an RT slot in the contradictory state `{rt_valid 0, resident 1}`. Regions 4-7 are
  all-zero, so dropping the `rt_valid` conjunct would have changed nothing observable. Region 3 was
  seeded into that state and `c14` re-pointed at it -- which also let the two negative phases test
  the two conjuncts *separately* rather than both hitting the resident bit.
- **M8** needed the saved shadow read **before any trap**. After the first `mret` the mutant and the
  correct design converge, because the restore writes `0xFFFFF` back either way; only a read taken
  before anything has trapped can tell a reset of `0` from a reset of `0xFFFFF`.

#### A contaminated first sweep, and the harness bug it exposed

**The first sweep reported 8/8 killed. That result was wrong, and the way it was wrong is worth
recording.**

M3 -- routing the CRBR-load validation through the fast-path-*exempt* signal -- was reported killed.
That contradicted the architectural reasoning behind the fix: once every load is RT-validated, the
state "the current region is itself non-resident" is unreachable by construction, so the mutation
should have no observable effect. A favourable result that contradicts the design is not evidence,
so it was re-measured:

| Measurement | Result |
|---|---|
| pristine, three consecutive runs | 64/0, 64/0, 64/0 -- the suite is **not** flaky |
| M3 in isolation, two runs | 64/0, 64/0 -- M3 **survives** |
| M3 inside the sweep | 63/64 -- "killed" |

**Root cause: the runner treats SandPiper exit code 1 as "warnings, proceed".** A transient
cloud-transpile failure that writes no new `sim/veda_core.sv` therefore leaves the *previous*
mutant's SystemVerilog in place, and the suite silently measures the wrong design. With mutants run
back to back, M3's iteration was measuring M2's code -- and M2 genuinely does kill
`r10_crossing_fault_neg`.

The second failure was mine: **the sweep recorded only how many tests failed, not which.** A bare
count cannot distinguish the intended kill from an unrelated one, which is exactly what let the bad
verdict through. Both are now fixed -- `sim/veda_core.sv` is deleted before every run (so a
transpile that produces nothing makes `iverilog` fail loudly instead of reusing stale output), and
every verdict records the name of each test that fell. The table above is from that hardened re-run.

#### M3 survives, and that is the correct result

M3 is reported as **surviving**, not quietly dropped. The mutation is real -- it reintroduces the
circular check the fix exists to avoid -- but it is **unobservable by construction**: every CRBR
load is RT-validated, so a region can only become "current" after the Region Table has vouched for
it, and the exemption it would then consult can never be reached in a state where it would answer
differently. M3 therefore guards a condition the rest of the fix makes unreachable. It is
defence-in-depth, not a behavioural gate, and no test can distinguish it without an RT-write
instruction that could revoke residency underneath a live CRBR -- which does not exist yet, and
whose obligation is recorded in Section 5.

## 5. Honest scope

- **OCJALR is deliberately untouched**, matching R10's stated boundary. It does not narrow PCC and
  does not cross a compartment boundary, so it loads no CRBR; a sealed-pair OCJALR inherits the
  caller's region. Recorded, not changed.
- **The Region Table is still reset-seeded** -- there is no RT-populate instruction and no authority
  gate for one. The `mret` restore is therefore **infallible** (it re-installs the saved pair with
  no RT re-validation), which is sound only while the RT is immutable after reset. The obligation
  carried forward from Sail stands: **a future RT-write instruction must refuse to clear residency
  on the current region and on any saved region.**
- **Multi-hart is untouched.** The single-hart answer does not generalize to "one hart evicts a
  region another hart's CRBR names"; that stays on the Phase 6 checklist.
- Two latent, unrelated issues were noticed in passing and deliberately **not** folded into this
  increment: `veda_smoke_m20_neg2.S` and `veda_smoke_mtvec_escape_neg.S` both write `0xFFFF` to CSR
  `0x7c3` intending the unbounded sentinel, which has been `0xFFFFFFFFFF` since RTL-3 (their sibling
  tests were updated; these two were missed, and currently pass only because a 65535-byte window
  happens to contain their recovery label). Also, seven testbenches on disk are not wired into the
  runner, including both dedicated OCJALR tests.
