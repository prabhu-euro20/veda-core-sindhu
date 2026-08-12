# RTL mirror 6 -- object residency and the page-out / page-in pair

**Date:** 2026-08-13. **Layer:** RTL (TL-Verilog `veda_core.tlv`). **Branch:** `sindhu`.
**Mirrors:** Sail `phase1-respec` DESIGN_02 Phase 2, increments 1 and 2.
**Baseline:** 64/64. **Result:** 69/69. **Mutation:** 12/12 + 16/16 + 14/16 (2 proven equivalent).

Landed as three commits rather than one, so a seed relocation and a new gate could not fail
together and be hard to attribute:

| | Content | Suite | Mutants |
|---|---|---|---|
| **6a** | `resident` byte, Bind gate 0x0A, writes, seeds, exclusions | 66/66 | 12/12 |
| **6b** | dereference-side residency across seven families | 67/67 | 16/16 |
| **6c** | page-out / page-in + the illegal-instruction umbrella | 69/69 | 14/16 |

## 1. The two decisions this increment forced

### Byte-aligned `resident` at +25, not bit-packed and not a 64-byte entry

DESIGN_02 recorded that `resident` + `cow` + `backing` do not fit in the 32-byte entry and that the
choice "should be made deliberately, not discovered by the RTL mirror one increment later". The
arithmetic is now **confirmed against the real file**: 25 bytes used (+0..+24), 7 spare, exactly as
projected.

The **functional** argument decided it, and it is about increment 6c rather than 6a. Page-in's
preserve-set is a *negative specification* -- `generation`, `owner_hart`, `Length`, `Perms` and
`retired` must survive, and they do so by **not being written**. There is no compiler check for a
line that should be absent. Byte-aligned, that arm is eight enumerated writes auditable by eye;
bit-packed, it becomes a read-modify-write of a shared byte where a preservation bug is invisible.

The **empirical** argument is that this file has already tried bit-level bookkeeping once. `retired`
is its only bit-level allocation, and three separate comment sites described it at offsets it had
not occupied since RTL-3. Saving a byte not yet needed, using the one discipline the file has
demonstrably failed to maintain, is a bad trade.

The counter-argument is real and is not dismissed: `resident` at +25 plus a future `cow` at +26
leaves 40 bits for `backing`, which DESIGN_02 has already judged insufficient. So this defers the
64-byte bump rather than avoiding it. It is deferred deliberately, because **what `backing` denotes
is still undecided** -- 56-bit address, 44-bit Object_ID, or something else -- and sizing the entry
before deciding the field the entry exists to hold is the wrong order.

### The refusals really trap

This was the genuine design question, not a transcription. Sail's page-out and page-in refuse via
`Illegal_Instruction()`. The RTL had **no general mechanism**: mcause 0x02 came from exactly one
signal, named by hand in two separate ternaries.

The available alternative was defensible. Populate and Destroy already have a refusal convention
here -- suppress the write, advance the PC, touch nothing else -- and inheriting it would have cost
nothing and kept the family consistent. The saturation refusal's *memory-level* safety would still
have held: no write, no corruption.

It was rejected because it makes the refusal **unobservable**. A refused page-out would be
architecturally indistinguishable from a successful one, so a pager could not tell that eviction
failed and would believe it had freed a frame it had not. And the value of this pair concentrates
in what it refuses -- the Sail-side sweep made that concrete: of six mutants, the four surviving a
suite that proved the mechanism *works* were all refusals or preservations.

So the existing single-purpose mechanism was generalized into `$veda_illegal_instr` rather than
duplicated. Adding a third hand-named signal to two ternaries would have worked, and would have
been the fourth place to forget next time.

## 2. First named offset constant in this file

`ODT_OFF_RESIDENT` is a deliberate departure from the surrounding literal-offset style. The entry
layout is hand-written in **six** places -- the file's own comment says three and undercounts. A
field added at +25 in five of six and +26 in the sixth compiles, elaborates, simulates, and produces
a permanently wrong residency with no diagnostic anywhere. That is RTL-3's Mutation W hazard, and
the existing mitigation for it (`ODT_ENTRY_BYTES` replacing a bare literal 32 in both strides) is
the direct precedent.

The 1=resident polarity is load-bearing too. `odt_mem` is pre-zeroed, so an omitted seed reads 0.
At 1=resident that omission traps every Bind in the corpus -- loud and unmissable. At 0=resident
the identical omission would make every never-written slot read resident and the gate a silent
no-op.

## 3. Two real defects found in existing work

**A dead assertion, live for three increments.** `tb_veda_smoke_m4_neg` states in its own header
that it verifies "two ways". Its second way read `odt_mem[16*5+9]` -- a probe left from the 16-byte
layout. Under the 32-byte layout byte 89 is entry 2's offset +25, a spare byte that is always 0, so
the conjunct was **vacuously true from RTL-3 onward**. Half of that negative test's stated coverage
had been proving nothing while the suite counted it.

It surfaced only because `resident` landed on exactly that byte: the dead conjunct came back to
life reading a real field with unrelated semantics and flipped the test to FAIL. A silently dead
assertion is worse than a missing one, because it is counted.

**Six stale layout comments, one of them dangerous.** The top-of-file header still described the
16-byte entry: 256 entries, owner_hart at "+10", "88 bits used of 128 available", and by implication
+11..+13 spare. Those bytes are `Length[39:24]` and `Perms`. A reader hunting spare space top-down
would have silently corrupted every object's bounds and permissions. The layout is now stated in one
place only, rather than patched in two.

## 4. What mutation testing found, and why it is the more useful number

### 6a -- 12 mutants

Ten died on the first pass. The two survivors were different in kind, and the distinction mattered
more than the count.

**Rebind's residency exclusion could be deleted with all 66 tests passing.** Not an equivalent
mutant -- a genuine hole. `$veda_rebind_ok` is `!sealed && valid && owner_ok`, and a paged-out
object is *valid* by construction, so an unguarded Rebind would write the paged-out entry's stale
Base into a capability whose Tag stays 1. The test could not see it because it rebound into a
register **untouched since reset**, which reads as sealed: the write was suppressed by the seal
check, not by the gate under test. **The test was measuring the wrong guard.** The real attack binds
a live capability first, then rebinds it onto the paged-out object.

**Destroy's residency clear is unobservable through the ISA, and provably so:** every reader of
`resident` is conjoined with `valid`, and Destroy clears valid. Rather than leave it as an
equivalent mutant, it is pinned as a *structural* assertion against `odt_mem` -- stated as such, not
blurred into a behavioural claim. "Currently unreachable" is a fact about today's readers, and
`cow` and `backing` will add readers.

### 6b -- 16 mutants

One Sail line becomes fifteen RTL sites. The first sweep reported 5/16 and both halves of that
number were wrong in instructive ways.

**Four of seven families were untested.** Deleting the residency term from OCS.C, NMC.W, NMC.D or
Atomic left all 67 passing -- each would have silently dereferenced a paged-out object at a stale
cached Base while the other six passed. NMC additionally needed `Permit_NMC_Compute` on the fixture
to reach residency at all; without it the permission cause fired first and the mutation was hidden
behind a legitimate refusal.

**Six mutants never ran.** Three pairs of cause chains share an identical tail, so tail-only anchors
matched twice. They were reported as ANCHOR-FAIL rather than silently counted, but the harness was
still measuring less than it claimed. It now asserts anchor uniqueness before trusting a verdict.

### 6c -- 16 mutants, 14 killed, 2 proven equivalent

Both survivors were investigated rather than assumed, and one of them **argued that the mutant was
the better design**.

**P3 -- the saturating bump.** A mutant replacing page-out's raw `+1` with the pre-existing
saturating expression survived, as expected: page-out requires `valid`, so the two agree on every
input page-out accepts. But examining *why* showed a raw `+1` **wraps** at the ceiling, and a
wrapped generation is exactly the ABA use-after-free that Milestone 16 introduced saturation to
eliminate. The refusal makes it unreachable today; the refusal is one gate. **The code was changed
to the mutant's form.** Both mechanisms now fail in the same direction, so if the refusal is ever
weakened the worst outcome is a frozen counter rather than a silently reused one.

**P16 -- the rd write-back.** Provably equivalent: the fall-through is `$alu_result`, whose chain
defaults to `64'b0`, and a Custom-0 opcode matches no ALU arm. The arm stays anyway -- the correct
value must be a stated decision, not an accident of an unrelated default two thousand lines away.
The comment on that arm originally claimed the opposite, and was corrected; asserting it without
checking is the failure this project exists to guard against.

**P11 was a real gap.** Page-out's authority gate could be deleted with all 69 passing, while
page-in's could not. The asymmetry was in the test: it attempted the unauthorized page-out on an
object already paged out, so residency refused it regardless of authority. **A negative test has to
make the condition it names the only reason for the refusal.**

## 5. The paging contract, as built

| | `veda.odt.page.out` | `veda.odt.page.in` |
|---|---|---|
| encoding | funct7 `0000101`, funct3 `001` | funct7 `0000101`, funct3 `000` |
| gate | authority & valid & resident & gen != 0xFFFFFF | authority & valid & not resident |
| writes | generation + 1, resident = 0 | Base = rs2[55:0], resident = 1 |
| preserves | everything else | **everything** else |
| refusal | mcause 0x02, mtval = the instruction | same |

The full cycle is verified end to end against two real linker-allocated buffers, so "the object
moved" is a fact about addresses: old Base `0x80000280`, new Base `0x80000380`, asserted to differ.

**Generation preservation is measured by counting**, because `generation` is architecturally
unreadable -- there is no CGet for it. The fixture sits at `0xFFFFFD`, **two** steps below the
ceiling, and the second step is the point: one step below, a wrongly-bumping page-in would saturate
to `0xFFFFFF`, which is indistinguishable from correct preservation. The mutation would hide inside
the saturation. Two steps down the behaviours separate into something countable -- two successful
page-outs before the refusal if preserved, one if bumped.

**owner_hart preservation is a multi-hart property proven in a single-hart core.** Page-out is gated
on authority, not ownership, so a pager may legitimately evict an object it does not own. Had
page-in reset `owner_hart`, any hart could then claim it -- object theft by triggering a page fault.
Observable here only through Bind's own 0x06 refusal.

## 6. Honest scope

- **A pre-existing Sail/RTL divergence was found and NOT closed.** All five ODT-family instructions
  raise `Illegal_Instruction()` on authority failure in Sail. The new pair now does. **Populate,
  Populate-Fast and Destroy still silently no-op**, so an unauthorized attempt at any of the three is
  architecturally indistinguishable from a successful one. The mechanism to fix it now exists
  (`$veda_illegal_instr`); wiring them in changes existing test expectations, so it is a separate
  increment rather than a quiet rider on this one.
- **Paging is not transparent, by design.** A holder whose object was paged out sees a trap and must
  re-Bind. That is the accepted cost of DESIGN_02's cached-Base decision.
- **The dereference-side residency term is unreachable through the ISA**, because page-out bumps
  generation and a stale capability therefore fails on 0x02 first. It is kept because that soundness
  argument is a property of the current producer set, not of the checker.
- **Page-out's rs2 field is not checked for zero.** Sail's encoding hardwires it; the RTL decode
  idiom tests only opcode/funct3/funct7, so the RTL accepts a wider encoding. Inherited from
  ODT-Destroy, which has the identical asymmetry.
- **Region residency is still not checked by the ODT-write family**, page-out and page-in included.
  Deliberately consistent with Populate/Destroy rather than diverging here, but it means an object
  can be paged into a domain whose own table is paged out. Should be settled for the whole family at
  once.
- **`backing` is still not built**, and its prerequisites are unchanged: a reader (no instruction
  reads any ODT entry field), a decision on what it denotes, and a handler-side way to identify which
  object faulted -- `mtval` carries `{cap_idx, cause}`, not an Object_ID.
- **DRAM latency is not modelled for the paging pair**, matching Populate/Destroy. For instructions
  that by definition touch backing store in any real machine, that is a deliberate call worth
  revisiting, not an inherited default.
