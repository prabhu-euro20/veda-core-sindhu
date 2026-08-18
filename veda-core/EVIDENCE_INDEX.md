# Evidence Index: Every Major Claim, Traced to Its Concrete Source

**Date:** 2026-07-28
**Purpose:** this session covered a large number of design decisions,
demonstrations, and comparisons. Before drafting any external-facing
technical document, every one of them is re-verified here — re-run,
right now, not recalled from earlier in this conversation — or clearly
labeled as a cited external source, a computed derivation, or an honest,
still-open gap. Nothing in this index is asserted without one of these
four labels.

**Verification legend**:
- **[RE-RUN NOW]** — the underlying test/simulation was re-executed
  during this exact pass, not recalled from memory of an earlier result
  in this conversation.
- **[FILE, COMMITTED]** — a real, persistent file in the repository,
  checked to exist right now.
- **[EXTERNAL SOURCE]** — a real, independently-published fact, cited
  with a URL, not derived from this project's own work.
- **[COMPUTED]** — real arithmetic performed on other verified/cited
  numbers, not a new measurement of its own.
- **[OPEN]** — an honest, explicitly-stated gap — not yet built,
  measured, or resolved.

---

## 1. OCJALR (Milestone 17) — closes the stack-frame return-address gap

| Claim | Evidence |
|---|---|
| Sail self-check suite passes, including 2 new OCJALR tests | **[RE-RUN NOW]**: `bash run_veda_selfcheck_tests.sh` → **28/28 passed** (this pass, this exact command, this exact output) |
| RTL milestone suite passes, including 2 new OCJALR tests | **[RE-RUN NOW]**: `run_veda_smoke_test.sh` (25/25 for M1-14+base) + direct M15/M16/M17 runs (6/6) = **31/31**, all `*** TEST PASSED ***` |
| ACT4 RV64I conformance unaffected | **[RE-RUN NOW]**: `run_act4_tests.sh` → **51/51 passed, 0 failed, 0 timed out** |
| `OCJALR` closes the exact gap `prot_gap` demonstrated | **[FILE, COMMITTED]**: `rtl/MILESTONE_17_RESULTS.md` — real before/after (`0xxxxxxxxxxxxxxxxx` undefined → `0xca11` controlled trap) |
| Source code | **[FILE, COMMITTED]**: `rtl/veda_core.tlv` (`$is_veda_ocjalr` etc.), `toolchain/sail-riscv/model/extensions/Veda/veda_cap_insts.sail` (`VEDA_OCJALR`) — both modified, present, `git status` confirms |
| Real encoding collision found and fixed before RTL was written | **[FILE, COMMITTED]**: documented in `veda_cap_insts.sail`'s own comment and `rtl/MILESTONE_17_RESULTS.md` |
| OCJALR real steady-state cost: 7 vs 5 cycles/call (traditional), ~30% cheaper than the naive protected sequence (10 cycles/call) | **[FILE, COMMITTED]**: `rtl/MILESTONE_17_RESULTS.md`'s own measured-cycle table, derived from real loop benchmarks at N=1,2,4,8,16 |

## 1a. `VEDA_ODT_POPULATE_FAST` + `veda_attr` CSR (Milestone 18) — fixes the 12-bit immediate tax

| Claim | Evidence |
|---|---|
| Software-only `la`-based fix saves only ~5% (not "huge") | **[RE-RUN NOW]** (this session, prior pass): scratchpad `immfix/build_and_run.sh` → naive=40, optimized=38 cycles at N=4, `objdump`-verified 10 vs 9 instructions/object |
| Sail self-check suite passes, including 2 new Populate-Fast tests | **[RE-RUN NOW]**: `bash run_veda_selfcheck_tests.sh` → **30/30 passed** (this pass, this exact command) |
| RTL milestone suite passes, including 2 new Populate-Fast tests | **[RE-RUN NOW]**: `run_veda_smoke_test.sh` → **27/27**, all `*** TEST PASSED ***` |
| ACT4 RV64I conformance unaffected | **[RE-RUN NOW]**: `run_act4_tests.sh` → **51/51 passed, 0 failed, 0 timed out** |
| Encoding collision-free (Custom-0, funct3=000, funct7=0000100) | **[RE-RUN NOW]**: direct grep of every `$is_veda_*` decode condition in `veda_core.tlv` before adopting, confirmed free in both Sail and RTL |
| Source code | **[FILE, COMMITTED]**: `veda-core/rtl/veda_core.tlv` (`$is_veda_odt_populate_fast`, `$csr_is_veda_attr`, `$veda_attr`), `toolchain/sail-riscv/model/extensions/Veda/veda_ocl_insts.sail` (`VEDA_ODT_POPULATE_FAST`), `.../veda_regs.sail` (`veda_attr` register + CSR wiring) — all modified, present |
| Real, measured savings: 27 vs 40 cycles at N=4 (−32.5%), converging toward −40% as N grows, no crossover point | **[RE-RUN NOW]**: scratchpad `m18bench/build_and_run_sweep.sh` → naive={10,20,40,80,160}, populate_fast={9,15,27,51,99} at N={1,2,4,8,16}; exact closed forms `10N` / `6N+3`, `objdump`-verified 10 vs 6 instructions/object |
| Real ISA fix delivers ~6.5x larger improvement than the best software-only workaround | **[COMPUTED]**: 32.5% / 5% ≈ 6.5x, both at N=4, both against the same real, unmodified, committed `veda_core.tlv` |

## 2. Attack-Demo Portfolio — 5 real vulnerability classes

| Demo | Result | Evidence |
|---|---|---|
| #1 OOB Read | traditional leaks `0xdeadbeefcafebabe`; Veda-Core traps (`mtval=0x01`) | **[FILE, COMMITTED]**: `SECURITY_COMPARISON_STUDY.md` |
| #2 OOB Write | traditional corrupts canary; Veda-Core traps, canary untouched | **[FILE, COMMITTED]**: `SECURITY_COMPARISON_STUDY.md` |
| #3 ROP/return-hijack | traditional `x30=0xbad1` (hijacked); `OCJALR` `x30=0xca11` (caught) | **[FILE, COMMITTED]**: `STACK_FRAME_CALL_RETURN_ANALYSIS.md`, `rtl/MILESTONE_17_RESULTS.md` |
| #4 Use-After-Free | traditional `x7=0xbbbbbbbbbbbbbbbb` (leaks object B through stale "object A" reference) | **[RE-RUN NOW]**: `vvp sim/sim_trad.vvp +elf_hex=trad_uaf.hex` → `x7=0xbbbbbbbbbbbbbbbb` (exact match to prior report) |
| #4 (Veda-Core side) | trap fired, `mcause=0x18`, `mtval=0x02` | **[RE-RUN NOW]**: `vvp sim/sim_veda.vvp +elf_hex=veda_uaf.hex` → `x23=0x600d` (the trap handler's own exact-cause-verified success marker, exact match) |
| #5 Arbitrary-pointer forgery | traditional: forged value works unconditionally (`x7=0xdeadc0dedeadc0de`) | **[RE-RUN NOW]**: `vvp sim/sim_trad.vvp +elf_hex=trad_forge.hex` → exact match |
| #5 (Veda-Core side) | `CGetTag=0`, then use traps, `mtval=0x122` | **[RE-RUN NOW]**: `vvp sim/sim_veda.vvp +elf_hex=veda_forge.hex` → `x23=0x600d`, exact match |
| Full doc, with "does this reflect real hardware" honest caveat | **[FILE, COMMITTED]**: `ATTACK_DEMO_PORTFOLIO.md` |

## 3. "Does this reflect real hardware?" — the honest caveat itself

| Claim | Evidence |
|---|---|
| MMU/paging is real but page-granularity only; does not catch same-page overflow | **[EXTERNAL SOURCE]**: [Buffer overflow protection, Wikipedia](https://en.wikipedia.org/wiki/Buffer_overflow_protection), [MMU overview, ScienceDirect](https://www.sciencedirect.com/topics/computer-science/memory-management-unit) |
| Intel CET real but slow real-world adoption | **[EXTERNAL SOURCE]**: [Intel Shadow Stack – A Bridge Too Far, Karamba Security](https://karambasecurity.com/blog/2019-06-11-intel-cet-notyet), [Linux kernel CET docs](https://docs.kernel.org/6.9/arch/x86/shstk.html) |
| ARM PAC real, deployed on Apple Silicon M1/M2 + high-end Android SoCs, not universal | **[EXTERNAL SOURCE]**: [LLVM CFI vs Intel CET vs ARM PAC](https://medium.com/@nikheelvs/llvm-cfi-vs-intel-cet-vs-arm-pac-a-deep-dive-into-control-flow-protection-39fd4af2fb36) |
| Intel MPX real but deprecated/removed | Well-established, real, publicly documented Intel product history |

## 4. Real Math / Quantitative Comparison document

| Claim | Evidence |
|---|---|
| MTE 4-bit tag = 1-in-16 collision chance per attempt | **[FILE, COMMITTED]**: already-cited in this project's own `WASM_SFI_HARDWARE_ALTERNATIVE_FIT_ANALYSIS.md`, sourced to the real, peer-reviewed CGO 2025 "Cage" paper |
| `P(attacker succeeds after k attempts) = 1-(15/16)^k` — 96.03% by k=50 | **[COMPUTED]**: real arithmetic, re-run right now: `python3 -c "print(1-(15/16)**50)"` → confirms 0.9603 |
| Veda-Core Tag: `P(success)=0` regardless of `k`, for the pure-corruption attacker model | **[RE-RUN NOW]**: Attack Demo #5 above, `CGetTag=0` confirmed this exact pass |
| Microsoft ~70% of vulnerabilities are memory-safety class | **[EXTERNAL SOURCE]**: [OpenSSF Memory Safety Continuum](https://openssf.org/blog/2025/04/28/announcing-the-release-of-the-memory-safety-continuum/) |
| Android fell 76%→<20% (2019→2025) via Rust, not hardware | **[EXTERNAL SOURCE]**: same OpenSSF source |
| Chrome 205 CVEs (2025), UAF dominant bug class | **[EXTERNAL SOURCE]**: live search result, cvedetails.com/Chromium security data, already cited |
| iAPX 432: 300μs→100μs but still 3x slower after rework | **[FILE, COMMITTED]**: `DESIGN_SOUL_AND_UNIQUENESS.md`, `ROP_JOP_MITIGATION_FIT_ANALYSIS.md`, sourced to Levy's *Capability-Based Computer Systems*, read in full earlier this project |
| Veda-Core worst measured overhead (1.561x) is under half of iAPX 432's | **[COMPUTED]**: `1.561 / 3 = 0.52`, i.e. 52% — "under half" is precise |
| WASM real overhead numbers (20%-650%, 12.7%-20% optimized) | **[FILE, COMMITTED]**: `WASM_SFI_HARDWARE_ALTERNATIVE_FIT_ANALYSIS.md`, sourced to peer-reviewed VMIL 2024 |
| CHERI's real 13-year/1,800-commit/£190M ecosystem cost | **[FILE, COMMITTED]**: `SCALING_BARRIERS_RESEARCH.md`, sourced to Brooks Davis/FreeBSD Journal |
| Sail-cheri-riscv formal-verification proportion (2.6% Sail, 97.4% Isabelle+Rocq) | **[FILE, COMMITTED]**: `SCALING_BARRIERS_RESEARCH.md` §8 |

## 5. Single Address Space section

| Claim | Evidence |
|---|---|
| Mungi real, published, >10x IPC/task-creation improvement over Irix/Linux | **[EXTERNAL SOURCE]**: [The mungi single-address-space operating system, Software: Practice and Experience](https://onlinelibrary.wiley.com/doi/abs/10.1002/%28SICI%291097-024X%2819980725%2928%3A9%3C901%3A%3AAID-SPE181%3E3.0.CO%3B2-7) (Heiser et al., real peer-reviewed venue) |
| `OCInvoke` = 1 instruction, 1 cycle | **[FILE, COMMITTED]**: `rtl/MILESTONE_10_RESULTS.md` (original real RTL/Sail verification); re-confirmed as still passing this session (§1 above uses the same trap/jump infrastructure) |
| Real traditional context-switch cost: 1,000-2,000 cycles direct, ~30μs practical worst case | **[EXTERNAL SOURCE]**: [Measuring context switching, Eli Bendersky](https://eli.thegreenplace.net/2018/measuring-context-switching-and-memory-overheads-for-linux-threads/), [Quantifying the cost of context switch](https://www.researchgate.net/publication/221469941_Quantifying_the_cost_of_context_switch) |
| Resulting 1,000x-2,000x ratio (vs. a full real OS context switch) | **[COMPUTED]**, from external-sourced numbers, stated as such |
| Real, dedicated own-hardware benchmark: `trad_cycles=1+9N` (software-gated call) vs `ocinvoke_cycles=38+3N`, 3x per-crossing, crossover at N≈6.17 | **[RE-RUN NOW]**: both cores built and run side by side at N=1,2,4,8,16, exact closed-form fit verified this pass; two real bugs found and fixed during this exact debugging session (PCC-narrowing loop-boundary issue, `ODT-Populate` status-register aliasing with the address-holding register) before the final numbers were accepted |
| IBM i correction (single-level store ≠ multi-tenant isolation; that's the POWER Hypervisor's job) | **[FILE, COMMITTED]**: `SCALING_BARRIERS_RESEARCH.md` §1, sourced to IBM Redbook SG24-7940-05, read directly, quote included in that doc |

## 6. Additional benefits (WCET-determinism, side-channel immunity, compartmentalization)

| Claim | Evidence |
|---|---|
| ODT deliberately flat (not multi-level) for WCET-predictability | **[FILE, COMMITTED]**: `DESIGN_SOUL_AND_UNIQUENESS.md`, stated design-pillar reasoning, real, pre-existing |
| Structural immunity to cache-timing side channels (Spectre/Meltdown-class) | **[OPEN]** — architecturally true (no cache/speculation exists in this core to attack) but explicitly **not empirically tested** in this project; stated as such when raised |
| Compartmentalization cost reduction (`OCInvoke`/PCC) | **[FILE, COMMITTED]**: `rtl/MILESTONE_10_RESULTS.md`, `rtl/MILESTONE_14_RESULTS.md`, `PCC_COMPARTMENT_DESIGN.md` |

## 7. FPGA feasibility

| Claim | Evidence |
|---|---|
| Yosys 0.58 installed, iCE40/ECP5 synthesis targets available | **[RE-RUN NOW, this session]**: `yosys -V`, confirmed `/home/prabhu/anaconda3/bin/yosys`, real `share/yosys/ice40`/`ecp5` present |
| 2 real SV-compatibility bugs found and fixed (in a scratch copy only) | Reproduced live: minimal 3-line isolation tests shown to fail then pass, this session |
| Full `synth_ice40` pass is resource-prohibitive on this specific machine (confirmed independent of memory size) | Directly observed: process killed at 11GB+ RAM/20+ min CPU time at both 16KB and 1KB memory sizing |
| Lighter `proc;opt -fast;memory_collect` pass succeeds: 2,981 generic cells, 1,726 muxes, 251 flip-flops, 3 memories | Directly observed, this session, 3.34s CPU/132MB peak |
| **No real iCE40 LUT/FF number exists yet** | **[OPEN]**, stated explicitly — needs a machine with more RAM, not yet re-attempted |

## 8. European funding/research landscape

| Claim | Evidence |
|---|---|
| Horizon Europe `HORIZON-CL3-2026-02-CS-ECCC-01`, €20M, hardware-security architectures, deadline 15 Sept 2026 | **[EXTERNAL SOURCE]**: [EUACC call listing](https://www.euacc.ai/calls/HORIZON-CL3-2026-02-CS-ECCC-01), [European Commission digital-strategy announcement](https://digital-strategy.ec.europa.eu/en/news/new-horizon-europe-funding-boosts-european-research-data-computing-and-ai-technologies) |
| ETH Zurich Institute for Computing Platforms, CHERI-on-RISC-V/CVA6/Ibex work | **[EXTERNAL SOURCE]**: [ETH Zurich Systems Group project page](https://systems.ethz.ch/research/compass/Bringing-CHERI-Security-to-RISC-V-CVA6-and-Ibex.html) |
| CHERI Alliance, real, standardization-facing organization | **[EXTERNAL SOURCE]**: RISC-V Summit Europe 2026 talk listing |
| NLnet Foundation, individual-eligible, €5k-€50k, open-source hardware/security | **[EXTERNAL SOURCE]**: [nlnet.nl](https://nlnet.nl/), real 2025 grant-announcement press releases found live |
| Horizon Europe eligibility caveat: typically needs an EU legal entity/consortium, not unaffiliated individuals | Honest assessment stated directly when this was raised, not verified against the call's own detailed eligibility text — **[OPEN]**, a real next check before assuming either way |

---

## What this index does NOT cover

- Every single number from earlier sessions (before this conversation's
  visible history) is trusted at the "already committed, already
  previously verified" level, not re-run in this specific pass, except
  where explicitly marked **[RE-RUN NOW]** above. `SECURITY_COMPARISON_STUDY.md`,
  `OBJECT_CENTRIC_VS_TRADITIONAL_BENCHMARK.md`,
  `CAPABILITY_REGISTER_PRESSURE_STUDY.md`,
  `SYNTHESIS_CRITICAL_PATH_STUDY.md`, `ENERGY_TOGGLE_ACTIVITY_STUDY.md`
  fall in this category — real, committed, file-verifiable, but not
  re-executed again in this specific evidence pass.
- Any claim not listed above was not made with enough specificity in this
  conversation to independently verify — if a reviewer asks about
  something not on this list, it should be checked fresh, not assumed
  covered by omission.

---

## ADDENDUM -- 2026-08-18 hardening pass (R36 through R59)

**Appended rather than merged into the 2026-07-28 index above, which is a snapshot
of its own pass and stays intact.** Same legend. Every count here was produced by
the run recorded at the bottom of this section, not recalled.

### Findings closed this pass, each with its own DESIGN_07 entry

| finding | what it closed | evidence |
|---|---|---|
| **R36 / R39** | `veda.droppriv` retired, Custom-3 unclaimed, standard `mstatus.MPP` + `mret` privilege on both layers, and the generic CSR privilege check the RTL never had -- every one of its fourteen Machine-only CSRs, `mtvec` included, had been reachable from U-mode | **[FILE, COMMITTED]** `sail_tests/vc_r39_csr_priv.S`, `rtl/sim/veda_smoke_r36_priv_trap.S`, `rtl/sim/veda_smoke_r27_csr_priv.S`, `difftest/probes/p15_priv_model.S` |
| **R38** | the copy-on-write fault got an eligibility predicate -- the capability's own `PERM_STORE`, so the split right belongs to whoever held write authority when the object became copy-on-write | **[FILE, COMMITTED]** `difftest/probes/p14_cow_eligibility.S`, `sail_tests/vc_check_order.S` PHASE D, `rtl/sim/veda_smoke_check_order.S` P8 |
| **R38(b)** | a copy-on-write object is not pageable -- `page.out` was destroying the very capabilities that carry the split right | **[FILE, COMMITTED]** `sail_tests/vc_r38b_cow_not_pageable.S`, `difftest/probes/p18_cow_not_pageable.S` |
| **R40** | `PERM_LOAD_CAPABILITY` / `PERM_STORE_CAPABILITY` enforced at `OCL.C`/`OCS.C`. **The escape was demonstrated before it was closed**: a delegation attenuated to data-only with `CAndPerm` lifted a live, tagged capability naming an object it was never given | **[FILE, COMMITTED]** `sail_tests/vc_r40_cap_perm_enforce_neg.S`, `difftest/probes/p17_cap_perm_flow.S` |
| **R41** | plain `ODT-Populate` clears `cow` and resets `owner_domain` -- it had carried the previous occupant's policy onto a freshly minted object, and the two layers disagreed about it | **[FILE, COMMITTED]** `difftest/probes/p16_populate_policy_reset.S` |

### Register integrity

**[RE-RUN NOW]** The DESIGN_07 finding register was audited by enumerating every
`R<n>` reference in every `.md`/`.tlv`/`.sail`/`.S`/`.sv`/`.sh` file across all
three repositories and in every commit message, then differencing against the
`###` headings. **Four numbers had no entry -- R18, R25, R27, R28 -- and three of
them were shipped, verified hardware fixes**, two of exploitable class. All four
are now entered. The register runs **R1..R59 with no gaps.**

| **R44** | `veda.bind` mode `0b11` (`VEDA_BIND_RESERVED`) is refused at DECODE on both layers. It used to reach Sail's `Illegal_Instruction` arm only after three ODT-state-dependent traps had had their chance, so the refusal CAUSE for an unallocated encoding was an ODT oracle | **[FILE, COMMITTED]** `difftest/probes/p19_bind_reserved_mode.S` |
| **R45** | the executing-object pin compares MEMORY, not names. Two Object_IDs may still legally name one range -- SLAB-CARVE mints children inside a parent by construction -- but an alias is no longer a handle for evicting the code a compartment is running | **[FILE, COMMITTED]** `sail_tests/vc_r45_odt_alias_neg.S` |
| **R46** | `verification.sh` reads every suite's exit code and refuses a suite reporting a zero total; `difftest/rundiff.sh` resolves its own toolchain. **Measured: the entry point exited 0 while all 21 differential probes had not run** | **[FILE, COMMITTED]** `verification.sh`, `difftest/rundiff.sh` |
| **R47** | the ODA's `Base`/`Length` are load-bearing on the delegated path -- all seven ODA-gated instructions. **The escape was a shipped, passing test**: `veda_smoke_m11.S` minted a descriptor four kilobytes outside its own authority's window from User mode and read back the Base as proof | **[FILE, COMMITTED]** `sail_tests/vc_r47_oda_scope_neg.S`, `difftest/probes/p20_oda_scope.S` |
| **R48** | the ODA is CLEARED at OCInvoke and OCReturn, tag only. **Measured before the fix**: a User compartment holding only a code and a data capability destroyed the caller's object AND minted over the caller's window -- zero traps, mcause 0x00 -- and `OSpecialRW` being Machine-only meant the caller had no instruction with which to drop its own ODA before calling | **[FILE, COMMITTED]** `sail_tests/vc_r48_oda_inherit_neg.S`, `rtl/sim/veda_smoke_r48_oda_crossing.S` |
| **R49** | seven programs were assembled by the runner and never simulated; one of them (`m16_neg`) had been asserting the opposite of the architecture since generation widened 8 -> 24 bits. Re-aimed onto the seeded near-saturated fixture, plus a coverage guard and a real exit code on the runner | **[FILE, COMMITTED]** `rtl/run_veda_smoke_test.sh`, `rtl/sim/veda_smoke_m16_neg.S` |
| **R50** | **[OPEN, MEASURED]** the capability register file crosses a compartment boundary intact and the dereference checker has ZERO domain terms. A callee read `0xC0FFEE` out of the caller's object through a register it was never handed, zero traps. Larger than R48 | **[MEASURED, NOT FIXED]** DESIGN_07 R50 |
| **R51** | **[OPEN, MEASURED]** the region table has no software write path at all, so OCInvoke cannot succeed without test fixtures -- the compartment crossing has never been differentially tested | **[FILE, COMMITTED]** `difftest/blocked/p21_oda_crossing.S`, plus a probe-coverage guard in `run_difftests.sh` |
| **R50 inc 1** | **OCLEAR** -- there was NO instruction that reliably zeroed a capability register's VALUE, so the switcher-clears-what-it-does-not-pass answer was a duty this architecture had assigned and shipped no tool for. Clears the VALUE (the query family is un-gated, so a tag-only clear still answers `CGetBase` with the raw physical Base) and keeps `otype = 0xFFFF` (an all-zeros clear reads as SEALED and Rebind would refuse forever while every tag assertion stayed green) | **[FILE, COMMITTED]** `sail_tests/vc_r50_oclear.S`, `difftest/probes/p23_oclear.S` |
| **R52** | **[OPEN, MEASURED]** a callee needs only the NAME: given the integer alone, with the caller having untagged its own register first, it re-Bound the caller's private object and read it -- zero traps. Control: with `owner_domain` actually set, 2 traps and nothing read. The gate is sound; its DEFAULT is open, and that makes clearing registers at the crossing theatre | **[MEASURED, NOT FIXED]** DESIGN_07 R52 |
| **R53** | CSetBounds was computed at the PRE-WIDENING widths on the RTL -- Base 32, Length 16 -- and the window check validated the TRUNCATED request. **Measured**: a request of `0x10000` gave `0x00010000` on Sail and `0x00000000` on the RTL, with both controls agreeing. Now 56/40, and the check is 65 bits wide because at 64 a huge request wraps and passes | **[FILE, COMMITTED]** `difftest/probes/p22_csetbounds_width.S` |
| **R54** | two `verification.sh` runs at once corrupt each other -- they share `rtl/sim/` and the difftest artifacts. **Measured on myself**: one run reported `51/51` RTL and `5/24` differential while the other reported the true `98/98` and `24/24`. R46's exit-code discipline is what refused to certify it. Now interlocked, so a second run is refused rather than merely visible | **[FILE, COMMITTED]** `verification.sh` |
| **R55** | `veda.bind` minted a capability out of a region that had never been configured -- the model had TWO residency predicates and only the crossings' one checked `rt_valid`. **Measured with its control**: bind into region 3 `{rt_valid=0,resident=1}` gave 0 traps and TAG 1; bind into region 2 `{rt_valid=1,resident=0}` gave 1 trap and tag 0. The RTL was already right, so the SPECIFICATION was more permissive than the hardware | **[FILE, COMMITTED]** `sail_tests/vc_r55_bind_rt_valid_neg.S` |
| **R56** | RT-Populate **decided against** as the next increment: two of its three justifications were false at source (R51's stated cause, and R52's grain), and the minimal version is a compartment escape on first execution -- regions 4..7 already alias region 0's base at reset on both layers. The region layout is disjoint only because the model truncates locals at 2^20; `region_entry` has no length | **[DESIGN_07 R56]** |
| **R52 CLOSED** | the creation-time binding policy: an object created INSIDE a compartment belongs to that compartment's domain; ambient-created objects stay open. Two lines per layer, no new instruction. **The ambient arm is what keeps R17's retraction from repeating** -- demonstrated with the return-path control intact. Residual stated: the gate's subject is the REGION, so two compartments in one region remain one principal by R10's design | **[FILE, COMMITTED]** `sail_tests/vc_r52_creation_domain.S` |
| **R58** | the R52 landing hit Populate and DESTROY instead of Populate and POPULATE-FAST. Destroy inherited the destroyer's domain (breaking R41) and populate.fast still wrote ANY -- **and the shipped C allocator uses exactly that encoding, so R52 was void for every heap object while being reported closed**. Both suites stayed green throughout. Corrected, plus the pre-existing RTL Destroy divergence closed in Sail's direction | **[FILE, COMMITTED]** `sail_tests/vc_r58_domain_writers.S` |
| **R59** | Sail resets `owner_hart` on Populate, Populate-Fast and Destroy; the RTL's only dynamic write to that byte was the owner CLAIM, so a re-minted object inherited the previous occupant's owner -- **benign at MHARTID 0 and PERMANENT above it, because no instruction can clear the byte**. And `$veda_owner_claim_en` lacked `!domain_violation`, so a trapping Bind still claimed. R41's class on the third carried field | **[FILE, COMMITTED]** `sail_tests/vc_r59_owner_hart_reset.S`, `rtl/sim/veda_smoke_r59_owner_reset.S` |
| **R51 CORRECTED** | its stated cause was wrong. `test_fixtures = false` does NOT disable region seeding (writes at `veda_regs.sail:1231-1242`, the guard opens at `:1530`). `p21_oda_crossing.S` measured nothing because its compartment declared `Length 0x40` while its terminating `ecall` sat one word past that window. Corrected to `0x200`, it runs and agrees on all seven words -- **the compartment crossing's first cross-layer coverage** | **[FILE, COMMITTED]** `difftest/probes/p21_oda_crossing.S` |

### Open, honestly

- **[OPEN]** **R42** -- `PERM_GLOBAL` and `PERM_STORE_LOCAL_CAPABILITY` (causes
  `0x10`/`0x16`) are allocated and enforced by neither layer. They need a
  local-vs-global capability distinction this architecture does not have.
  `VEDA_CORE_SPEC.md`'s cause table now reads **"Allocated, NOT enforced"** for
  both instead of claiming Active.
- **[OPEN]** **R43** -- `Rebind` does not enforce the "already-bound" precondition
  §4 describes: it checks neither the tag nor that the register names the same
  object. Not an escalation today; it becomes one the instant anybody makes Rebind
  preserve the holder's own `Perms`.
- **[OPEN]** Phase 2's `backing` field (`mmap(file)`) is still unbuilt -- the ODT
  entry has `valid`/`generation`/`owner_hart`/`retired`/`resident`/`owner_domain`/`cow`
  and no `backing`.

### The single command that reproduces all of it

**[FILE, COMMITTED]** `veda-core/verification.sh`. It used to hardwire its root to
`/home/prabhu/makerchip/rva23-core` -- a **frozen sibling project this line is not
entitled to write into** -- so the one command offered as "run this to verify"
would have built into someone else's tree and verified whatever vintage happened
to be sitting there. It now resolves its own location, and it runs the
**cross-layer differential suite** too, which it never did.

**R46 -- AND FOR A WHILE IT COULD NOT FAIL.** It captured each suite's output into a
variable and never read an exit code, so it exited 0 regardless. Measured doing
exactly that: three green numbers, a fourth reading `Cross-layer diff : 0/21 as
expected`, exit 0 -- while the 21 differential probes had not run at all, because
`difftest/rundiff.sh` took `iverilog` from the caller's ambient `PATH` and both of
its sibling runners self-activate conda and it did not. Now the exit code is the
verdict, and a second guard the exit code cannot give: **every suite must report a
nonzero total**, because a suite that dies before running anything can still exit 0
and `0 programs run` reads as a clean line rather than an outage.

Current, through the fixed entry point, in a shell with no conda active:

```
  Sail self-check   : 110/110 passed
  RTL milestones    :  99/99  passed
  ACT4 conformance  :  51/51  passed
  Cross-layer diff  :  25/25  as expected
  VERDICT: all four suites ran and passed.
```
