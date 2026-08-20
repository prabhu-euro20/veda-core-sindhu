# Superseded early-milestone tests (R88)

These fourteen files sat in `sail_tests/` named `veda_*.S`, from before the `vc_*.S`
convention. **The runner globs `vc_*.S`, so it never matched them.** They looked
exactly like coverage -- in the tests directory, named as tests, naming real
mechanisms -- and nothing ran them. All fourteen were measured and **all fourteen
fail**, having drifted behind the landings the live corpus absorbed.

They are kept rather than deleted because nothing here is discarded, and because
they record what the early milestones actually checked.

**They are superseded, not lost coverage.** Every mechanism they name is covered by
the live corpus, measured by encoding across all three suites:

| mechanism | encoding | `vc_` | difftest probes | RTL |
|---|---|---|---|---|
| CSeal | `0x5b,0x1,0x10` | 51 | | |
| CUnseal | `0x5b,0x1,0x11` | 1 | 0 | 1 |
| CSetBounds / Exact | `0x5b,0x1,0x08/0x09` | 3 | 4 | 4 |
| OCA | `0x5b,0x1,0x0a` | 13 | | |
| query family (CGetBase/Perm/Tag) | `0x5b,0x0,0x00-0x03` | 63 | | |
| NMC-add | `0x0b,0x2` | 4 | | |
| Veda-Atomic | opcode `0x2b` | 4 | 1 | 9 |
| ODT populate | `0x0b,0x0,0x03` | 74 | | |
| ODT destroy | `0x0b,0x1,0x03` | 10 | | |

**A note on how that table was produced, because the first version of it was wrong.**
CSetBounds and the Veda atomics initially read as **zero** coverage -- from patterns I
guessed rather than looked up. The real encodings are `funct7 = 0x08` for CSetBounds
(`veda_cap_insts.sail:206`) and opcode **`0x2b`**, not `0x0b`, for the atomics
(`veda_atomic_insts.sail:61`). Had the guessed numbers been trusted, two of these
files would have been called lost coverage and repaired at length for nothing.

## The files

| file | what it named |
|---|---|
| `veda_test.S`, `veda_neg.S` | the original Milestone smoke and its negative |
| `veda_cseal_test.S`, `veda_cunseal_test.S`, `veda_cseal_unauth_neg.S`, `veda_seal_enforce_neg.S` | the sealing family and three negatives |
| `veda_csetbounds_test.S` | CSetBounds |
| `veda_oca_test.S`, `veda_oca_neg.S` | OCA and its negative |
| `veda_capquery_test.S` | the metadata query family |
| `veda_nmc_add_test.S`, `veda_nmc_add_neg.S` | NMC-add and its negative |
| `veda_atomic_test.S` | the Veda atomics |
| `veda_odt_lifecycle_test.S` | populate / bind / destroy lifecycle |

**Do not move a file back without repairing it first**, and if you do, rename it to
`vc_*` so the runner actually globs it -- which is the whole point of R88.
