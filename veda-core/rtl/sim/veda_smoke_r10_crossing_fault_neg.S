.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL-5 (R10, DESIGN_07 Tier G) NEGATIVE: a domain crossing
    // into a NON-RESIDENT region must raise an explicit
    // VEDA_CAUSE_REGION_FAULT (0x09) and commit NOTHING -- not the PCC
    // narrowing, not the c15/IDC install, not the PC redirect.
    //
    // Region 2 is seeded rt_valid=1 / rt_resident=0 (its table is paged
    // out). The operands come from the RTL's reset CRF seeds, because a
    // region-2 capability genuinely CANNOT be built at runtime -- Bind is
    // residency-gated and every derivation instruction carries Object_ID
    // through unchanged. That is the mechanism working; the seeds model
    // the legal state of a capability minted while the region was still
    // resident and held across its page-out.
    //
    //   c12 = sealed region-2 CODE  (Execute|Invoke, otype 0x0042)
    //   c13 = sealed region-2 DATA  (Invoke only,    otype 0x0042)
    //   c14 = region-3 SENTRY       (Execute,        otype 0xFFFE)
    //
    // The two phases test the TWO CONJUNCTS of the residency check
    // separately, which is why they name different regions:
    //   region 2 = {rt_valid 1, resident 0} -- a paged-out domain, so
    //              phase A fails on the RESIDENT bit.
    //   region 3 = {rt_valid 0, resident 1} -- an unconfigured slot whose
    //              resident bit is garbage-true, so phase B fails on
    //              RT_VALID despite residency saying yes. That arm is the
    //              only witness for the fail-closed conjunct: rt_valid is
    //              otherwise write-only in the RTL, so dropping it from the
    //              check would be invisible without this fixture.
    //
    // Phase A -- OCInvoke c12, c13. The pair passes ALL NINE of OCInvoke's
    // capability checks (both tagged, both sealed, matching otype, invoke
    // on both, execute on code, non-executable data), so the FIRST and
    // ONLY failure is the region gate. That isolation is the point: a pair
    // failing an earlier check would report 0x09 for the wrong reason.
    // cs1 = c12 -> mtval = (12<<5)|0x09 = 0x189.
    //
    // Phase B -- OCReturn c14. cs1 = c14 -> mtval = (14<<5)|0x09 = 0x1C9.
    //
    // The load-bearing assertions are cause 0x09 (NOT 0x11, which is what
    // each cause mux's fall-through arm would report if the explicit 0x09
    // arm were missing) and that execution never entered the compartment.
    // The handler redirects mepc to an explicit label rather than adding a
    // byte offset, so nothing here depends on how a pseudo-instruction
    // happens to expand.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0
    li   x17, 0                            // trap counter

    // Precondition: the seeds really are present and well-formed, so a
    // failure below is about the gate and not about a missing fixture.
    .insn r 0x5b, 0x0, 0x03, x5, x12, x0  // cgettag  x5, c12 -- expect 1
    .insn r 0x5b, 0x0, 0x04, x6, x12, x0  // cgettype x6, c12 -- expect 0x42
    .insn r 0x5b, 0x0, 0x04, x7, x14, x0  // cgettype x7, c14 -- expect 0xFFFE
    // The saved-CRBR shadow must read the EMPTY sentinel before any trap
    // has occurred. This is the only assertion in the suite that can see a
    // sentinel of 0 instead of 0xFFFFF: after the first mret the mutant and
    // the correct design converge, because the restore writes 0xFFFFF back
    // either way. Read it here, before anything traps, or the distinction
    // is unobservable.
    csrr x23, 0x7C7                        // veda_saved_region -- expect 0xFFFFF

    // ---- Phase A: OCInvoke into the paged-out domain.
    .insn r 0x5b, 0x1, 0x12, x0, x12, x13 // ocinvoke c12, c13 -- must REGION_FAULT
    j    done                              // wrongly-succeeded invoke never reaches after_a
.balign 4
after_a:
    mv   x8,  x18                          // mcause from A -- expect 0x18
    mv   x9,  x19                          // mtval  from A -- expect 0x189

    // ---- Phase B: OCReturn through the region-2 sentry.
    .insn r 0x5b, 0x1, 0x16, x0, x14, x0  // ocreturn c14 -- must REGION_FAULT
    j    done                              // wrongly-succeeded return never reaches after_b
.balign 4
after_b:
    mv   x10, x18                          // mcause from B -- expect 0x18
    mv   x11, x19                          // mtval  from B -- expect 0x1C9

    // The CRBR must be untouched by both faulting crossings: still region 0.
    csrr x15, 0x7C6                        // expect 0
    // Nothing may have been saved -- no trap left a non-root domain.
    csrr x16, 0x7C7                        // expect 0xFFFFF (empty sentinel)
    mv   x20, x17                          // trap count -- expect 2
    li   x22, 0x600D
    j    done
.balign 4
trap_handler:
    csrr x18, mcause
    csrr x19, mtval
    addi x17, x17, 1
    // t5/t6 deliberately, NOT t2: t2 IS x7, which holds the cgettype c14
    // precondition. An earlier draft used t2 here and the handler silently
    // overwrote that result with 1 -- the assertion then read 0x1 instead
    // of 0xFFFE and the test failed for a reason that had nothing to do
    // with the mechanism under test.
    li   t5, 1
    bne  x17, t5, th_second
    la   t3, after_a                       // first fault -> collect A
    csrw mepc, t3
    mret
th_second:
    la   t3, after_b                       // second fault -> collect B
    csrw mepc, t3
    mret
done:
1:
    j 1b
