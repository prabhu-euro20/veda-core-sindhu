# RTL-9 (R11(b)) -- the executing-object pin

**Result: 72/72 smoke (71 pre-existing + 1 new), 51/51 ACT4, 7 of 8 mutants killed.**

## What this closes

R11(a) made the three domain crossings revalidate their code object, which closes *entering* an
object that was evicted while you were not running it. It could never close the other half:
eviction of the object you are **currently executing**. Instruction fetch compares the program
counter against PCC's cached Base and Length and never re-reads the Object Descriptor Table, so no
amount of checking at a crossing helps once execution is already inside.

PCC now carries the object's **name**, and the instructions that can change an entry refuse on it.
One compare, on a cold path, instead of a table read on every fetch -- the same trade DESIGN_02's
cached-Base decision already settled.

## The consumer set, enumerated rather than recalled

Every instruction that can change an entry's identity or backing:

| instruction | in the pin's set | why |
|---|---|---|
| `veda.odt.populate` | yes | repopulating a still-valid slot bumps generation AND repoints Base |
| `veda.odt.populate.fast` | yes | same, wide path |
| `veda.odt.destroy` | yes | clears valid/resident, bumps generation |
| `veda.odt.page.out` | yes | clears residency, bumps generation |
| `veda.odt.page.in` | **no** | already refuses unless the object is non-resident, and an executing object is necessarily resident -- closed for an independent reason that predates this increment |

Populate is the one that nearly got missed, and missing it would not have left a partial fix -- it
would have left a **bypassable** one, since Populate does everything Destroy does and more. Three
times in this increment a multi-site fix landed at all but one site, which is why the set above was
read off the decoder instead of assembled from memory.

## The pin is slot-addressed here, and name-addressed in Sail

This is a deliberate divergence, not a transcription error.

Sail resolves an entry as `base(region) + the FULL 24-bit local`, so name and slot are in bijection
and comparing names *is* comparing slots. This core models 256 locals per region and resolves with
`local[7:0]` only, so **many names share one slot**: Object_ID 436 and Object_ID 180 land on the
same 32 bytes. The 36-bit `id_hi` tag exists to catch exactly that, but it is consulted on the two
read paths only (`$veda_odt_valid`, `$veda_check_odt_valid`) -- neither ODT write arm looks at it.

A name compare here was therefore bypassable in one instruction: `veda.odt.destroy 436` while the
core executes object 180 passes the pin and clears the running object's descriptor.

The predicate is now `same region && same local[7:0]`, which is exactly "the same entry" for this
index function. Full-name equality implies it, so the slot compare **subsumes** the name compare
rather than trading one guarantee for another. Each layer expresses the pin in whatever uniquely
identifies a descriptor in that layer.

## The pin traps; the gates beside it do not

`$veda_odt_populate_violation` and `$veda_odt_destroy_violation` reach only their definitions, the
`$reg_write` suppression and the two `odt_mem` write gates. Neither is in `$veda_trap_taken` or
`$veda_illegal_instr`, so Populate and Destroy refuse **silently** in this core while Sail raises
`Illegal_Instruction` for the identical gates. `veda_smoke_m4_neg.S` and `veda_smoke_m11_neg.S`
both depend on that silence -- they drop privilege, populate, and keep executing.

That divergence predates this increment and is **not** changed here. What is changed is that the
pin refuses to inherit it: `$veda_executing_pin_refusal` is its own signal and joins both chains,
exactly as the page-out and page-in refusals already do. A silent refusal would tell a pager an
eviction succeeded when it did not, and the pager would then reuse memory it does not own -- worse
than either trapping or succeeding. Software has to learn it may not evict the running object,
because the correct response is specific: abandon the frame first, then retry.

## Verification

`sim/veda_smoke_r11b_pin.S` + `sim/tb_veda_smoke_r11b_pin.sv`:

- **A1/A2/A4** page-out, Destroy and Populate-Fast on the running object all refused. A2 runs after
  a trap round-trip, so it also proves mret restored the NAME along with the bounds.
- **A5** the alias: Object_ID 436 refused. Impossible to construct on Sail; reachable only here.
- **A6** no half-apply: 180 re-Binds afterwards and its Base still reads back as the compartment.
  Suppressing the write and raising the trap are two separate signals, so a mutant that keeps the
  trap and drops the suppression passes every other check.
- **B** the saved name pins too -- all three refused from inside a handler, where PCC belongs to no
  object and only the saved name can be doing the work.
- **C** the release: the same instruction on the same object succeeds once OCRETURN abandons the
  frame. A pin that never released would be denial of revocation.
- **D** the over-refusal control: an unrelated live object stays evictable while a compartment runs.

### Mutation

| | verdict |
|---|---|
| N1 pin disabled entirely | KILLED |
| N2 **the bypass** -- compare names again instead of slots | KILLED |
| N3 pin refusal no longer traps | KILLED |
| N4 populate's ODT write no longer suppressed (trap still fires) | KILLED |
| N5 destroy's ODT write no longer suppressed (trap still fires) | KILLED |
| N6 saved-MEPCC term dropped | KILLED |
| N7 abandoning the frame does not release the saved name | **SURVIVED** |
| N8 crossings never install the name | KILLED |

**N7 is an equivalent mutant, and the same one survived on the Sail side (M8) for the same reason.**
The depth guard masks the missing clear: the abandon sets depth to 0 in the same step, and the saved
term is gated on `depth != 0`, so the stale name is unreadable. The two mechanisms are redundant
*with each other* -- either alone is unobservable, but removing both would pin a code object forever.
Two independent sweeps, on two independently written implementations, found the same redundancy.
That is a useful signal that the mirror really is a mirror.

N4 and N5 exist because the test was extended before the sweep ran: reasoning about what a
write-suppression mutant would do exposed that nothing checked for a half-applied refusal. The check
came from predicting the mutant, not from watching one survive.

## One test bug found, and it was the test

The first run reported FAILED with `x30 = 0xD09E` and `traps = 8` -- the assembly's own assertions
had all passed. The testbench asserted `0x600D` on `x29`, which is an mcause **record** holding 2,
not a marker. The RTL was right and the check was wrong, the same shape recorded for Milestone B.
PART B now sets an explicit marker (`x18`) instead of borrowing a record register.
