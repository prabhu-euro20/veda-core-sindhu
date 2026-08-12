# Labelling convention -- what the prefixes mean

Two independent numbering schemes exist in this project, and they briefly collided because both
started with the letter "R". This document fixes the convention so the collision cannot recur.

## `R1` .. `R9`, `Rev-A` .. `Rev-F` -- security/robustness FINDINGS

These live in `veda-core-linux` `design/DESIGN_07_ROBUSTNESS_AND_SECURITY_HARDENING.md`. They are
adversarially-derived **weaknesses in the design**, each with a proposed hardware-native fix. "Rev-"
findings are the revocation family (taking access back). They are **not implementation steps** and
they are **not ordered work items** -- a finding stays open until some increment closes it.

Examples: `R1` (intra-slab use-after-free), `R2` (ODT entry has no integrity protection), `R5`
(make non-speculation a machine-checked contract), `R9` (the 16-entry CRF rationale does not
transfer to purecap).

**Always cite these with their document**: write "DESIGN_07 R2", never a bare "R2".

## `RTL-1`, `RTL-2a`, `RTL-2b`, `RTL-3`, `RTL-4` -- RTL mirror INCREMENTS

These are the ordered steps of porting the Sail-verified Phase 1 respec into the hardware
description. Each is one commit, verified green with mutation testing before the next begins.

| Increment | What it does | Status |
|---|---|---|
| `RTL-1` | CAndPerm (rights attenuation) | done, 53/53 |
| `RTL-2a` | 32-byte tag granule + capability-access alignment | done, 57/57 |
| `RTL-2b` | the 256-bit capability format | done, 58/58 |
| `RTL-3` | ODT entry widen + populate split + PCC widen | next |
| `RTL-4` | generation counter 8 -> 24 bits | after RTL-3 |

The `a`/`b` split of increment 2 is deliberate and is **not** in the Sail ordering: see
`RTL_MIRROR_02A_TAG_GRANULE_RESULTS.md` for why the granule must land before the format (landing
the format first leaves a real forgery window that the test suite would report as green).

## The one cross-scheme marker

`INTERIM BRIDGE RTL-3:` in `veda_core.tlv` marks a **deliberate** narrowing that exists only until
increment RTL-3 lands. It exists because in Verilog a deliberate narrowing and a forgotten widening
are textually identical -- there is no type error to catch the difference. **`grep 'INTERIM BRIDGE'`
must return zero once RTL-3 is complete.**
