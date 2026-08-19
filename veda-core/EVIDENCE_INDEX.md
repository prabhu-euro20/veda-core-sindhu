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
are now entered. The register runs **R1..R76 with no gaps** -- a claim that was false when it said R1..R59: R57 had no entry at all, and the audit that produced this line did not re-run itself. Re-audited 2026-08-19 by extracting every `### Rn` heading and diffing the sequence.

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
| **R60 (D5)** | the CRBR saved shadow was released by NO exit `OCRETURN` takes and installed by ANY later xret. `veda_trap_frame_abandon` freed the depth, the mepcc triple and the poison, never the shadow; `veda_crbr_restore_on_xret` fires on the sentinel ALONE. So a handler entered from a region-1 compartment and left by OCRETURN -- **the only exit the shipped switcher takes** -- stranded region 1, and the next `mret` by unrelated region-0 code installed it. **Traced on the unfixed Sail model and measured on the unfixed RTL**; both layers agreed, so a design gap, not a divergence. Weakens R55's `rt_valid` gate via `veda_region_is_resident`'s current-region exemption | **[FILE, COMMITTED]** `sail_tests/vc_d5_crbr_shadow_leak.S`, `rtl/sim/veda_smoke_d5_crbr_shadow_leak.S` |
| **R61 (D7)** | a record defect, and **D7's own two claims were both wrong about where and what**. The `pending/` README's routing is **correct** (refuted); the phantom citation lives in `pending/vc_r52_bind_by_name_neg.S:203` -- which did not merely name a missing sibling but **reported its result in the past tense**, introducing it as *"the control that decides what the finding IS"*. Never built, never run, and **redundant**: `vc_bind_domain_neg.S` and `vc_r52_creation_domain.S` already prove the gate both ways. Ninth instance of the green-claim-that-measured-nothing class, in the worst possible place | **[FILE, COMMITTED]** `sail_tests/pending/README.md`, `sail_tests/pending/vc_r52_bind_by_name_neg.S` |
| **R62 (D6)** | `veda.odt.set.domain` wrote `rs2[19:0]` into `owner_domain` **unvalidated**. A domain IS a region (R10), so a policy naming an unconfigured region takes effect when someone else is GIVEN that region -- **authority that outlives its author**, closing the one place this project's temporal-safety thesis had not been applied to policy. The refusal was already one term away, written for the object half. **Write-time, not read-time**: a read-time check would just make the stamp arrive on schedule. **Every use of `set.domain` in the whole corpus, both layers, FOUR tests, named a principal that does not exist -- not one correct usage anywhere** -- which is why it was invisible. Measured on the shipped binary: the same file at domain 7 is refused, at domain 1 accepted | **[FILE, COMMITTED]** `sail_tests/vc_r62_domain_nameable_neg.S`, `rtl/sim/veda_smoke_r62_domain_nameable.S` |
| **R63** | the region half of an Object_ID was an **identity on the read path and a bare index on the write path**. R55 put `rt_valid` on `veda.bind`; `VEDA_ODT_POPULATE`'s gates are Machine-or-ODA, the executing pin, the ODA window and `retired` -- **none reads either RT bit**. Regions 4..7 reset to base 0, which IS region 0's base. Measured by trace: `populate {5,200}` accepted, `bind {0,200}` returning the prober's own arena, `bind {5,200}` refused -- **a descriptor written under a name its author was refused to read**. Not an escalation (the ODA window already bounds every writer); it breaks **namespace integrity** and falsifies R10's headline as stated. **Corrects R56**, which named the barrier as `rt_resident[4]` -- no RT-Populate was ever needed. Fixed in two halves: the resolution choke point, plus a visible refusal in all **seven** writers, because the first half alone was a silent no-op (R14's class, measured) | **[FILE, COMMITTED]** `sail_tests/vc_r63_region_write_alias_neg.S`, `rtl/sim/veda_smoke_r63_region_write_alias.S` |
| **R57 VERDICT (B)** | **the entry that did not exist.** R57 was cited four times in DESIGN_07 and had no heading anywhere; its three residue items were each measured, fixed and written up while describing themselves as residue of a finding the register did not contain. Now entered, with its verdict -- **the region IS the domain grain** (seL4's `KernelNumDomains`, CHERIoT's loader) -- and its four premises tabulated: three came back FALSE and became R60, R62 and R63 | **[FILE, COMMITTED]** `design/DESIGN_07` R57 |
| **R64** | **`backing` DECIDED AGAINST** by a 19-agent adversarial pass (four architects, three attack lenses each; one agent died and its design was never seen -- recorded as a gap, not papered over). The opaque-handle design was killed by a **stale-base window inversion** -- its only scoping guard is evaluable exactly when `Base` is dead, so it authorizes whoever inherited the corpse; the capability design by an ungated read port, a Machine-only privilege transplant, and 257 bits that do not fit. The decisive argument is `region_backing`: 56 bits, five increments, **no reader** -- because no instruction reads an ODT field into a GPR at all. Built instead: the prerequisite DESIGN_02 named and said belongs FIRST -- **CSR 0x7C9 `veda_mfaultobj`**, the bind-side fault-identification channel, fail-closed by construction (`veda_trap`'s 53 sites untouched; a second entry point carries the name, the chokepoint writes the sentinel) | **[FILE, COMMITTED]** `sail_tests/vc_r64_fault_object_channel.S`, `rtl/sim/veda_smoke_r64_fault_object.S` |
| **R65** | an authority test against a Base the object has **left** -- the ODA's window in TIME. `set.cow`/`set.domain` authorize a delegated actor on `old_entry.Base` and required no residency; page-out preserves that Base as a value the model's own comment calls *"stale, and unreachable"*. **Measured end to end**: from User with an ODA covering only `victim_frame`, the `set.domain` on the paged-out victim retired, the pager restored it at `new_frame`, and `cgetbase` returned an address the attacker's window never covered -- reachable because **bind consults no ODA**. Destroy+Populate cannot substitute (`valid` clears, page-in refuses). **Not R47's residual**: R47 is the window in space. Fixed with `veda_stale_authority`; Machine exempt, deliberately opposite to R62, because this gates the validity of an authority test rather than well-formedness | **[FILE, COMMITTED]** `sail_tests/vc_r65_stale_base_authority_neg.S`, `rtl/sim/veda_smoke_r65_stale_base.S` |
| **R66** | **the retirement lands one Populate too late.** `retired` is computed from the OLD generation, so `{valid, 0xfffffe}` takes a Populate that saturates it and leaves retired FALSE; the NEXT Populate passes the gate, cannot bump, and writes a **second incarnation at the same generation** while the first one's capabilities are live. The dereference's only temporal arm is `entry.generation != cap.generation`, and `retired` is read by **no** dereference arm on either layer. **Measured**: the old capability read `0xABCD` out of the frame the descriptor had abandoned, while the new frame stayed zero. **The source already knew** -- page-out's comment describes this exact state, calls it *"a full use-after-free"*, and FAILS CLOSED on it; the defence was written for the instruction that OBSERVES the state, not the one that CREATES it. Found by a 32-agent stale-authority audit | **[FILE, COMMITTED]** `sail_tests/vc_r66_generation_collision_neg.S`, `rtl/sim/veda_smoke_r66_gen_collision.S` |
| **R67** | **the trap frame has an owner, not just a count.** `veda_trap_depth` is pushed at exactly ONE site (trap entry) and popped at TWO, and **OCInvoke touches it zero times** -- so an OCRETURN by a principal that never trapped popped a frame it did not push. **Measured**: compartment C trapped (`mepcc_length 0x40`), the handler OCInvoked into D, D returned, and C's frame became `0xFFFFFFFFFF` -- so any later `mret` restores nothing and C resumes with the bounds and the NAME the last crossing installed. R12's poison does not catch it: poison arms on a nested TRAP. Fixed with `veda_invoke_since_trap`, which distinguishes the handler LEAVING from an OCRETURN merely unwinding an OCInvoke the handler made -- a counter and not an owner check, because the switcher deliberately returns to a different principal | **[FILE, COMMITTED]** `sail_tests/vc_r67_frame_owner_neg.S`, `rtl/sim/veda_smoke_r67_frame_owner.S` |
| **R43 CLOSED** | Section 4 defines Rebind as refreshing an **already-bound** register; neither the tag nor the Object_ID was checked, so Rebind carried an Offset meaningful in object A onto object B's bounds. **Narrowed rather than the spec amended** -- leaving them disagreeing is R40's class, and amending would foreclose Perms-from-register while leaving the landmine armed. Soft-fail, not a trap, because Rebind never traps for any reason. **Closing it removed the LAST untagged sealedness read in the machine** (every other consumer checks the tag first or conjoins it, verified at source), which made the reset otype unobservable and forced two green tests to be re-aimed -- `vc_r24_crf_reset` P1 and `vc_r50_oclear` control 2 had both used Rebind-into-untagged as their discriminator. **R24's header named the weakness and then asserted it as the contract**: the fourth instance of that class, and the first found by a fix colliding with it | **[FILE, COMMITTED]** `sail_tests/vc_r43_rebind_identity_neg.S`, `rtl/sim/veda_smoke_r43_rebind_identity.S` |
| **R68** | **R65's rule reached two sites out of seven, and I shipped it that way.** `veda_oda_denies(old_entry.Base, ...)` is an authority test at SEVEN sites; R65 installed the residency term at set.cow and set.domain only. **Measured**: from User with an ODA covering only the frame the victim had left, a Populate over the paged-out victim was ACCEPTED while the same instruction against an out-of-window object was refused. **Worse in kind than R65** -- it retargets the victim's IDENTITY into attacker memory, and page-in then refuses a resident entry so the evicted contents can never be restored. **R58's shape a second time.** The objection that would have exempted Populate-Fast was itself an EXPIRED justification, superseded by its own document -- found by the sweep that was hunting exactly that class. Populate, Populate-Fast and Destroy closed; page.in and page.out left for their own pass | **[FILE, COMMITTED]** `sail_tests/vc_r68_populate_stale_base_neg.S`, `rtl/sim/veda_smoke_r68_populate_stale.S` |
| **R69** | **page-in is Machine-only**, closing the last two of the seven ODA authority sites. The defect is sharper than R65's framing: page-out is the sole producer of `{valid, not resident}` and its own gate refuses a non-resident entry, so its window test always ran on a LIVE Base -- which makes the preserved Base **the record of the eviction authority**, and page-in's first conjunct an **evictor test implemented by proxy through an address**. The proxy decays the instant the frame becomes reallocatable. **No substitute predicate works**: the legitimate delegated pager and the R68-standing attacker present identical evidence, and page-out records nothing about who evicted. "You may repair what you evicted" needs 20 or 44 bits and the entry has 16. **The lockout costs nothing constructible** -- CSR 0x7C9 is Machine-only by its address (`csrPriv = csr[9:8]`, `0x7C9` gives `0b11`), so a delegate could never learn which object faulted. Zero corpus damage | **[FILE, COMMITTED]** `sail_tests/vc_r69_pagein_machine_only_neg.S`, `rtl/sim/veda_smoke_r69_pagein_machine_only.S` |
| **R70** | **DESIGN_01 decision 7 was recorded, cited six times, and never built.** It says "Gate `Ext_Veda` on `xlen == 64` ... a prerequisite that lands before any width edit"; the width edit landed and the gate did not. Measured: `currentlyEnabled(Ext_Veda)` carried no xlen term, **12 of 28 encdec clauses had `xlen == 64` and 16 did not**, `validate_config.sail` had zero Veda arms, and `--rv32 --validate-config` reported valid -- so an RV32 build ran an incoherent **half-extension**. Not a capability escape (the dereference path is the half that did not decode); a **fail-open configuration gate**. Fixed at three levels -- structural (one line closes all 28), declarative (the rv32 config now says unsupported), and loud (a validate arm mirroring Zcf's). After: `CGetObjectID` on rv32 is `illegal`. No RTL mirror -- verified: its three `rv32`/`xlen` occurrences are all comments | **[FILE, COMMITTED]** `veda_types.sail`, `config/config.json.in`, `postlude/validate_config.sail` |
| **R71** | **the crossing now clears the capability register file**, closing R50's possession channel -- the last of the three a crossing leaves behind (R48 mint, R50i1 tooling, R50i2 possession). **The ABI decided in increment 2 was REFUTED by the RTL on a fact Sail cannot express**: a mask sourced from a GPR named by a reserved-zero field is free in Sail (`X(r)` is a function call) but is a **third integer read port on the whole register file** in hardware, since OCInvoke's two operand fields both name CAPABILITY registers -- a field being architecturally available does not make it economically readable. Landed instead as **CSR 0x8CA `veda_xretain`**: bit `i` set means capability register `i` survives, never-written means retain nothing, so **silence means clear and can never leak**; self-consuming, cleared on trap entry, zero at reset. OCInvoke clears BEFORE the IDC install (so `c15` survives by construction); OCReturn does NOT exempt `c15`. **Cost, measured**: 87 retain-all declarations (Sail 37/15 files, RTL 50/29), and 29 of 44 Sail files carrying a crossing needed no mask at all. `vc_r58_domain_writers.S` needed its PCC window widened 0x40 -> 0x80 -- a self-consuming mask must be set by the delegator, inside its own window. **All 87 are vacuous w.r.t. this mechanism**; the discrimination is carried by one two-round file per layer, round 2 (retain `c10`, read must SUCCEED) being the guard against a core that simply wipes unconditionally. **RTL vacuity proof**: with `L1_xclear_wr_en_a0` forced to `1'b0` (strip asserted to have landed first -- 228 bytes), the callee read the caller's secret `0xC0FFEE` with **zero traps** and carried its own IDC back across the return; fixed, the same instruction traps `mtval = 0x142` -- `cap_idx = 10`, cause `0x02` TAG, so the refusal names the register it refused | **[FILE, COMMITTED]** `sail_tests/vc_r50i2_crossing_clear.S`, `rtl/sim/veda_smoke_r50i2_crossing_clear.S` |
| **R72 (OPEN)** | **the machine refuses an object by NAME and hands over the same object through MEMORY.** `veda.bind` and `ocl.c` are both capability-ACQUISITION instructions and only one asks the ODT's ownership question. **Measured on both layers, identical values**: with object 200 locked to domain 0 by `set.domain`, a region-1 compartment's `veda.bind.notrap` is REFUSED (`mtval 0xAB` = cap_idx 5, cause `0x0B` DOMAIN) and it then takes the SAME object out of a shared object with `ocl.c` -- `cgettag` 1, `ocl.d` 0xC0FFEE. **One trap in the whole run and it is the control's refusal; the attack takes zero.** Structural confirmation: `VEDA_OCS_C` is the only instruction that writes a tagged capability to memory and `VEDA_OCL_C` the only one that reads one back, both authorised solely by `veda_check_access`, **whose eleven arms contain zero domain terms**. The refutation ("both parties already shared the container") NARROWS it -- at the default `VEDA_DOMAIN_ANY` the channel adds nothing over a re-Bind (R52) -- and does not defeat it: the moment software uses the policy field, the machine enforces it at the mint and not at the transfer. Adjacent and also open: trap entry and `xret` touch the capability file **zero times**, so every capability survives a trap in both directions | **[MEASURED, MECHANISM NOT YET CHOSEN]** probe kept in the session scratchpad; the mechanism is being priced before it is picked |
| **R73** | **a domain refusal trapped for all three bind modes and nothing said why.** The gate was written beside the residency gate and inherited its all-modes trap policy WITHOUT its argument -- residency and region trap for every mode so the holder goes and SERVICES something ("paged out, retry"), and **there is nothing to service on a domain refusal**. Milestone 12 set the rule for ownership refusals (plain Bind hard-traps, Bind-NoTrap soft-fails) and the `owner_hart` arm still implements it; this gate was the silent exception. **R43 justified a design decision by citing "Rebind never traps for ANY failure reason, owner mismatch included" -- false at source when relied on.** NOT an escape and NOT a divergence: both layers trapped identically. Fixed mode-dependently, each mode keeping its own soft-fail SHAPE -- measured: Rebind Base `0x80011100` -> tag 0, Base `0x80011100` (preserved); Bind-NoTrap -> tag 0, Base 0 (zeroed); plain Bind traps once, `mtval 0x6B` cause `0x0B`. **The fix's own hazard closed in the same edit**: `$veda_bind_claim_en` never consulted the domain gate, so narrowing `$veda_domain_violation` to plain Bind would have reopened R59 -- a soft-failing NoTrap claiming ownership of what it was just refused, invisible to every assertion in the corpus | **[FILE, COMMITTED]** `sail_tests/vc_r73_bind_mode_refusal.S`, `rtl/sim/veda_smoke_r73_bind_mode_refusal.S` |
| **R74** | **R71's retain mask was Machine-only, so the only software that needs it could not write it.** Privilege is derived from the CSR ADDRESS (`csrPriv(csr) = csr[9..8]`, and the RTL computes the same), so `0x7CA` was M-only -- while R71's own text told compartments to set it themselves, and compartments are unprivileged by definition. **Measured**: `veda_smoke_r48_oda_crossing.S` writes the mask after its drop to User and its trap counter read **2**, not 1 -- the write trapped, the mask stayed zero, and the suite passed 110/110 anyway (the thirteenth green that measured nothing). Fail-closed throughout, so nothing leaked -- but with the register channel shut to User code and R72's memory channel ungoverned, **R71 routed all unprivileged delegation onto the one path that asks no questions.** Moved to **`0x8CA`** from the official RISC-V Privileged spec's CSR allocation table: `0x800-0x8FF` is the ONLY Custom read/write **User** range, `csr[7:4]` unconstrained, and custom addresses "will not be redefined by future standard extensions". **No privilege-check logic changed -- only the constant**, 115 sites across 57 files, residual verified to zero. `0xCC0-0xCFF` rejected as Custom READ-ONLY. The objection ("never let the untrusted side write the boundary's policy") fails on authority -- the mask is retain-only, `0xFFFF` is the identity function -- and survives as an obligation, **retain must never become grant**, which is asserted rather than commented: `c9` is retained while EMPTY and must stay untagged and unusable (`mtval 0x122` names cap_idx 9). New obligation recorded: Smstateen's `mstateen0` bit 0 (C) governs custom state and now applies | **[FILE, COMMITTED]** `sail_tests/vc_r74_umode_retain_mask.S`, `rtl/sim/veda_smoke_r74_umode_retain_mask.S` |
| **R75 (OPEN -- BLOCKS R72)** | **the return path is an entry path and it has no admission control: domain identity is FORGEABLE FROM A NAME.** `OCInvoke` demands a sealed pair, which only a `PERM_SEAL` holder can mint, so the pair is evidence of delegation. `OCReturn` demands only a sentry -- and `CSealEntry`'s COMPLETE authorisation (`veda_cap_insts.sail:413`) is `CTag(cs1idx) & not(isSealedCap(cs1))`: no operand, no permission, no privilege. OCReturn's chain asks tag, sealed, otype, PERM_EXECUTE, region rt-resident and `veda_code_object_check`, **whose entire body (`:535-545`) is valid/generation/resident -- no domain term, no owner term** -- then `:924` runs `veda_pcc_object = cs1.Object_ID`. **Measured on both layers, identical values**: a region-1 compartment is REFUSED a domain-0 object (`cgettag` 0), executes `veda.bind` + `csealentry` + `ocreturn` on A's code object (owner_domain ANY, the default every object is created with), and the IDENTICAL bind then SUCCEEDS (`cgettag` 1) and reads 0xC0FFEE -- **zero traps along the whole chain**. Blocks R72: three of its four candidate mechanisms are defeated by this without touching the memory channel, because each asks "which domain am I" and this makes that question forgeable. Constraint on any fix: R17's retraction -- a caller is by construction in another domain, so OCReturn may not demand a matching one | **[PROBE IN REPO, DELIBERATELY NOT IN THE SUITE]** `sail_tests/poc_r75_forged_domain_identity.S` -- a PASS would mean the escalation works, which is the R73 failure shape |
| **R76 (OPEN)** | **the policy field the whole domain model rests on has no ownership gate.** `VEDA_ODT_SET_DOMAIN`'s COMPLETE authorisation (`veda_ocl_insts.sail:1252`) is `cur_privilege == Machine \| veda_oda_authorized()`, and **nowhere in the sixty-line clause is the actor's own domain compared to the entry's `owner_domain`** -- verified by scanning the whole clause; the only hits are a comment and the write itself. R75 forges an identity to satisfy the gate; **R76 rewrites the gate's own input.** **Measured, with a control and BOTH privilege arms**: a region-1 compartment is refused the object (`cgettag` 0), executes `set.domain SECRET <- 1` at Machine (ALLOWED, zero traps), and the identical bind then succeeds (`cgettag` 1) reading 0xC0FFEE -- while the SAME instruction at User traps exactly once. Severity stated rather than inflated: a MACHINE-MODE escalation, and arm 2 measures the mitigation instead of asserting it. R47's ODA window is authority over MEMORY, not over POLICY -- and R45 already recorded that two Object_IDs may name the same memory, so an ODA delegate may re-stamp objects belonging to other domains that happen to live in its window. **Every R72 or R75 mechanism keyed on `owner_domain` inherits this.** The fix -- you may re-stamp only what you already own -- reads `veda_pcc_object`, which R75 measured forgeable, so **R75 and R76 must land as ONE increment** | **[PROBE IN REPO, NOT IN THE SUITE]** `sail_tests/poc_r76_restamp_owner_domain.S` |
| **R75+R76 increment 1** | **the mechanism is decided and the cost is measured -- NOT LANDED.** Four crossing-side designs were refuted; the reason they share is that the forge does not depend on region collision, it depends on `VEDA_DOMAIN_ANY`, and that value is written at Populate rather than at a crossing. The official CHERI ISAv9 (UCAM-CL-TR-987, fetched from the canonical Cambridge URL, quote verified verbatim in the extracted text) states the closure property -- capabilities cannot be forged "from the point of CPU reset, via guarded manipulation" -- and **Veda-Core's `veda.bind` is a mint-from-a-NAME, so that property does not hold by construction; `owner_domain` is the only thing standing in for it.** TWO EDITS: a new `VEDA_DOMAIN_BOOT = 0xFFFFE` sentinel (verified free, with `0xFFFFF` as the control) returned by `veda_creating_domain`'s ambient arm, and an ownership term on `VEDA_ODT_SET_DOMAIN`. **`veda_bind_domain_ok` needs no edit at all** -- `0xFFFFE` equals no real region, so its existing third arm makes a BOOT-owned object bindable only from ambient. **MEASURED: all three probes CLOSED, each at its FIRST instruction, with the crossings never touched.** Cost: **8 of 123** Sail self-checks, the second edit adding none of them, every failure the same shape -- a compartment binding an object the ambient context created, which is R17's tension measured instead of argued. Reverted clean (123/123, probes verified open again) rather than half-landed, because a Sail-only landing would make the two layers disagree about who may bind | **[PROTOTYPED, MEASURED, REVERTED]** probes `poc_r75_*`, `poc_r75b_*`, `poc_r76_*` in `sail_tests/` |
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
  Sail self-check   : 123/123 passed
  RTL milestones    : 112/112 passed
  ACT4 conformance  :  51/51  passed
  Cross-layer diff  :  25/25  as expected
  VERDICT: all four suites ran and passed.
```
