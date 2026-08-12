# Phase 2, increment 1 -- object residency: the ODT starts becoming the memory map

**Date:** 2026-08-12. **Layer:** Sail (`veda-core-sail-riscv`, branch `phase1-respec`).
**Implements:** DESIGN_02 mechanism 1 (object-granular demand paging), first of three fields.
**Baseline:** 76/76. **Result:** 79/79.

## 1. What landed

`odt_entry` gains a `resident` bit, and using a non-resident object raises an explicit
**`VEDA_CAUSE_RESIDENCY_FAULT` (0x0A)**. That is the first step of DESIGN_02's central claim: with
`resident`, plus `backing` and `cow` in later increments, one object-indexed structure does what a
page table, a VMA list and a swap map jointly do elsewhere. No TLB, no Sv39, no satp.

Thirteen `odt_entry` construction sites had to be updated. Sail names every field at every site --
there is no record-update shorthand anywhere in the Veda extension -- so adding the field produced
thirteen compile errors and forced an explicit decision at each one. That property is worth naming,
because the RTL mirror will not have it.

## 2. The decisions, and why

### 2.1 Residency is checked at BOTH Bind and dereference

DESIGN_02 says "On Object-Bind (or first dereference)". That parenthetical is doing a great deal of
work, and the answer is **both**, for different reasons.

The dereference re-check computes its address from **`cap.Base`** -- the capability's *cached* copy
-- never from the live entry. A page-out leaves `valid` true (the object still exists) and does not
bump `generation` (only Populate and Destroy do). So **nothing existing would notice**: a capability
minted while the object was resident, held across an eviction, would read and write whatever now
occupies that memory.

Bind-only would therefore have been unsound. Bind-side checking is still worth having -- it invokes
the pager before a capability with a meaningless Base is minted -- but it is the dereference term
that closes the hole.

**The DESIGN_08 region precedent deliberately does not transfer.** Region residency is checked at
Bind only, and correctly so: it governs whether a domain's *table* is paged in, and by dereference
time the capability has already cached everything it needs from that table. Object residency governs
the *backing memory the cached Base points at*. Same word, different referent, opposite conclusion.

The dereference term is also **free**: both checkers already read the entry unconditionally, so no
additional ODT access is added. Two edits cover all eight dereference sites.

### 2.2 Residency is checked LAST among the entry-derived tests

Adding the field makes distinct conditions coincide. A never-populated slot is now both invalid and
non-resident; a destroyed object is both stale and non-resident. Checked too early, each would start
reporting 0x0A -- telling a pager to fetch an object that never existed, or to resurrect one that was
deliberately revoked.

Stated positively: **a residency fault means the object EXISTS and is merely absent.** Not-found and
destroyed are different, earlier, and not recoverable. `vc_residency_ordering` pins all three
outcomes in one run.

### 2.3 A separate cause (0x0A), not a reuse of REGION_FAULT (0x09)

The two demand different repair. 0x09 says *page the domain's table in*; 0x0A says *fetch this
object's contents from backing, allocate a Base, set resident, retry*. Collapsing them would send the
pager after the wrong thing.

### 2.4 The claim carries residency over

`claimed_entry` is written back on every successful Bind and Rebind, and it now carries
`resident = e.resident`. This is the highest-consequence single line in the increment. Writing
`true` would let **any Bind mark any object resident**, defeating the mechanism in one word; writing
`false` would make the second access to every object fault.

### 2.5 Populate establishes residency; Destroy clears it

Populate and Populate-Fast write `resident = true` explicitly -- that is precisely how DESIGN_02's
handler repairs a fault. Destroy writes `false` for state hygiene; it is deliberately unobservable,
since `valid = false` traps first and a revoked object must not look pageable.

### 2.6 No residency mirror in the capability's flags

DESIGN_01 floats a "residency-mirror" as a candidate tenant of the capability's opaque flags bits.
**Refused.** A residency bit cached in a register is exactly the stale-cache hazard this field exists
to close -- a register claiming "resident" while the table disagrees is strictly worse than no bit at
all. Residency is table-only, read fresh on every use.

## 3. Verification

| Stage | Result |
|---|---|
| Baseline | **76 / 76** |
| With the mechanism and three new tests | **79 / 79** |

Three tests, three distinct claims:

1. **`vc_residency_fault_neg`** -- Bind of a non-resident object raises 0x0A (not 0x05), mints
   nothing (destination untouched, tag not even cleared), and leaves **mepc on the faulting
   instruction itself**. That last assertion matters: a residency fault must be *resumable*, since
   the whole mechanism depends on re-executing after the pager runs.
2. **`vc_residency_ordering`** -- never-populated stays 0x05, absent-but-existing is 0x0A,
   wrong-owner stays 0x06. Three causes, one run.
3. **`vc_residency_deref_neg`** -- the dereference gate, which is the term that closes the actual
   hole.

### 3.1 Why the third test needed a seeded capability

The first two tests bind a non-resident object, so **Bind faults first and neither ever reaches a
dereference**. The bind gate was therefore well covered and the dereference gate -- the one that
matters -- was not covered at all.

Reaching that state requires a capability that already names a non-resident object, and no
instruction sequence can build one: Bind is residency-gated, and Populate is precisely what
establishes residency. *That is the mechanism working, not a test inconvenience.* So `c12` is
reset-seeded to name the non-resident object, exactly as the region fixtures are, modelling the legal
state of a capability held across an eviction. It is deliberately well-formed in every other respect,
so residency is the first and only thing that can stop it.

### 3.2 Mutation testing

Six mutants, each reverting exactly one decision. Every pattern asserts an exact expected match
count before building, and every verdict records **which** tests fell -- not just how many.

| Mutant | What it reverts | Result | Tests that fell |
|---|---|---|---|
| **M1** | the Bind residency gate | 77/79 -- KILLED | `residency_fault_neg`, `residency_ordering` |
| **M2** | the dereference gate (the stale-Base hole) | 78/79 -- KILLED | `residency_deref_neg` |
| **M3** | the claim's residency carry-over | 79/79 -- **SURVIVED** | -- |
| **M4** | residency checked before validity | 77/79 -- KILLED | `bind_notfound_neg`, `residency_ordering` |
| **M5** | Populate carries residency instead of setting it | 41/79 -- KILLED | **38 tests** |
| **M6** | the cause collapsed into REGION_FAULT (0x09) | 76/79 -- KILLED | all three residency tests |

Pristine re-verify afterwards: **79/79**, sources byte-identical to the pre-sweep backup.

Three of these are worth reading rather than counting:

- **M2 is the one that matters.** It is the only mutant that touches the term closing the actual
  security hole, and it is killed by the only test that reaches a dereference. Without
  `residency_deref_neg` the entire suite would have stayed green with that gate removed.
- **M4 fell on a PRE-EXISTING test** (`vc_bind_notfound_neg`) as well as the new ordering test.
  That test was written long before residency existed, and it catches the ordering violation on its
  own, because putting residency before validity turns "never existed" (0x05) into "paged out"
  (0x0A). The invariant is therefore asserted from two independent directions.
- **M5's breadth is correct, not alarming.** Making Populate *carry* residency instead of
  *establishing* it means every test that populates-then-binds now faults -- which is most of the
  corpus. A one-word change to a foundational write path taking down half the suite is exactly the
  shape of a load-bearing decision.

#### M3 survived, and that is the right result

M3 is reported as surviving rather than quietly dropped or "fixed" to reach a prettier 6/6. The
residency gate fires *before* the claim, so any object reaching the claim is provably resident --
which makes `resident = true` and `resident = e.resident` **identical in every reachable state**.
It is an equivalent mutant.

The line as written is still correct rather than accidentally correct: it says *a claim is not a
repopulate*, and it stays right if the gate is ever moved or reordered. But no test can distinguish
the two, and inventing one would be manufacturing evidence rather than gathering it.

## 4. Two process failures found this increment, both recorded rather than smoothed over

**A self-inflicted contaminated sweep.** A new test file was created *while a mutation sweep was
running*. The runner globs `vc_*.S`, so it entered the corpus mid-sweep (the total visibly jumped
78 -> 79) without the fixture it needed -- meaning it failed unconditionally, under pristine and
under every mutant alike. Its "kill" was spurious, and every later mutant would have been too. Caught
by noticing the total change; sweep stopped, sources restored, corpus frozen before restarting.
**Rule: never touch the corpus while a sweep is running.**

**A silently stale build.** The `c12` seed was present in the source, typechecked clean, and appeared
in the generated C++ -- yet the running binary did not have it (`cgetbase c12` returned zero while
the neighbouring seeds worked). Deleting the generated C++ and forcing regeneration fixed it
immediately. cmake's dependency tracking for the Sail -> C++ step had not regenerated after a `.sail`
edit.

This is **the same failure class as RTL-5's stale SandPiper transpile**: a build step silently
reusing prior output, so the suite measures a design that is not the one on disk. Both toolchains,
same shape. The mutation harness now deletes the generated model before every build and verifies it
was recreated, so a mutation can never be "applied" to a binary that does not contain it.

## 5. Honest scope

- **`backing` and `cow` are NOT in this increment.** Only `resident` landed. Without `backing` there
  is nowhere for a handler to fetch from, so the fault is currently raised and reported correctly but
  cannot yet be *repaired* in the model. The mechanism is real; the pager is not written.
- **There is no evict instruction**, so a non-resident object can only be reached by reset seeding.
  A test that binds while resident, evicts, then dereferences cannot be written yet. The seeded
  capability models that state faithfully, but it is a model of it, not a live transition.
- **Whole-object granularity only.** DESIGN_02 flags that a 1 TiB object cannot fault as one unit and
  may need per-object residency sub-tracking. The corpus already contains a 128 KiB object, so this
  limit is live, not theoretical. Not solved here, and the passing tests should not be read as
  solving it.
- **COW is bypassable as DESIGN_02 currently describes it** -- found while grounding this increment,
  recorded for the next one. Bind mints `Perms = e.Perms` verbatim, with no attenuation, on all three
  bind modes; CAndPerm writes only the register and never the table. So a domain that can name a
  COW object's Object_ID can simply re-Bind it and get a writable capability. COW must be enforced by
  hardware attenuation at Bind, not by software having handed out attenuated capabilities.
- **`PERM_STORE_VIOLATION` (0x13) had zero test coverage** across the whole corpus, despite being the
  path DESIGN_02 plans to reuse for the COW fault. **Now closed -- see Section 6.**

## 6. Follow-on: closing the rights-attenuation enforcement gap

Grounding this increment surfaced a gap worth more than the cause code it was first noticed as.

The corpus exercised CAndPerm only as a **metadata** operation: `vc_candperm.S` strips permissions
and inspects the result with `cgetperm`/`cgettag`; `vc_candperm_neg.S` checks the sealed-source
soft-fail. **Neither ever attempts an access with an attenuated capability** -- zero `ocs.d` between
them. So nothing anywhere proved that removing a right actually *blocks* anything. Attenuation was
tested as bookkeeping, never as enforcement.

Consequently both `VEDA_CAUSE_PERM_LOAD_VIOLATION` (0x12) and `VEDA_CAUSE_PERM_STORE_VIOLATION`
(0x13) had **zero coverage**, despite both being implemented.

**`vc_candperm_enforce_neg.S`** closes it in five phases, and phases 3 and 5 are what make it a
real test rather than two trap assertions -- they prove the attenuation is **precise**, removing
exactly the named right and leaving the other intact. A blanket "capability is now useless"
implementation would pass phases 2 and 4 and fail these.

1. full capability round-trips (positive control, so a later failure cannot be blamed on setup)
2. Permit_Store cleared -> `ocs.d` traps **0x13**, `mtval` `0x33`
3. the same capability **still loads**, and reads the **original** value -- which also proves the
   refused store never reached memory
4. Permit_Load cleared -> `ocl.d` traps **0x12**, `mtval` `0x92`
5. the same capability **still stores**

**Result: 80/80.** Mutation, two mutants each deleting one previously-uncovered check:

| Mutant | What it removes | Result | Tests that fell |
|---|---|---|---|
| **M1** | the `Permit_Store` check entirely | 79/80 -- KILLED | `candperm_enforce_neg` |
| **M2** | the `Permit_Load` check entirely | 79/80 -- KILLED | `candperm_enforce_neg` |

Both fell on **only** the new test. That is the measurement of the gap: deleting either check
outright left **79 of 80 tests passing**. Both halves of Veda-Core's rights attenuation -- the
whole point of CAndPerm -- could have been silently removed and every gate in the project would
have reported green.

This matters for what comes next rather than only for tidiness: DESIGN_02's copy-on-write reuses
the store-side path as its COW fault. Building COW on it before this would have been building on a
trap no test had ever fired.
