.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL M21-restore mirror (MILESTONE_21_RESTORE_RTL_RESULTS.md):
    # automatic PCC restore-on-mret, ported from the Sail side's own
    # vc_pcc_auto_restore_on_mret.S. Three real, independently-checkable
    # properties, matching that file's own three phases exactly:
    #   Phase 1 (x30=1): positive automatic restore -- a handler that
    #     touches NEITHER veda_pcc_* NOR veda_mepcc_* at all still
    #     resumes with the original narrow bounds correctly restored,
    #     AND those restored bounds are genuinely enforced (a deliberate
    #     post-check fetch past the real boundary still hard-traps).
    #   Phase 2 (x30=2): explicit override still honored -- the handler
    #     deliberately clears veda_mepcc_length before mret; execution
    #     resumes UNBOUNDED, not re-narrowed, proving software retains
    #     full control.
    #   Phase 3 (x30=3/4): nested-trap staleness -- a second, unrelated
    #     trap fires INSIDE the first handler, before its own mret. That
    #     second trap's own capture must NOT overwrite the first trap's
    #     real saved bounds (already unbounded at that point, so the new
    #     conditional-capture guard correctly skips it) -- the first
    #     handler's own later mret still correctly restores the original
    #     bounds.
    #
    # Object_IDs 140-146, grep-audited fresh against every existing
    # Object_ID literal in the rtl/sim assembly sources before picking
    # the only ones in use; 140-146 is a clean, unused block).
    #   140 = shared type-authority (Seal|Unseal), reused across phases
    #   141/142 = Phase 1 CODE/DATA   143/144 = Phase 2 CODE/DATA
    #   145/146 = Phase 3 CODE/DATA
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, dummy_type_authority
    slli t0, t0, 32
    li   t1, 0x00400300
    or   t0, t0, t1
    li   x1, 140
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate -- type-authority

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT since R75/R76, so an object is no
    // longer public by accident: R75 bound another domain's CODE object by name
    // and installed that domain's identity in three instructions, and R75b did
    // the same through a TYPE AUTHORITY. Objects a compartment must bind are now
    // DECLARED, next to where they are created. Region 0 is this file's flat
    // layout showing through -- DESIGN_07 records principal granularity as the
    // open question that no declaration can settle.
    li   x2, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    # ============================== PHASE 1 ==============================
    la   t0, phase1_entry
    slli t0, t0, 32
    li   t1, 0x00440402                   # Length=0x0044 (68B) -- exact byte budget through the
                                          # nop at offset 0x40, confirmed via objdump: `j fail`
                                          # (the deliberate escape) sits at offset 0x44, the first
                                          # byte genuinely outside this bound.
    or   t0, t0, t1
    li   x1, 141
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # -- CODE_1
    li   x1, 142
    li   x2, 0x8002000000400400           # DATA_1 dummy, Invoke only
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 140
    .insn i 0x0b, 0x5, x2, x1, 0          # bind c2, x1 -- type authority
    li   x1, 141
    .insn i 0x0b, 0x5, x0, x1, 0          # bind c0, x1 -- CODE_1
    li   x1, 142
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1, x1 -- DATA_1
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    li   x30, 1
    // R50 increment 2: this file predates the crossing's retain mask and
    // measures a different mechanism, so it declares RETAIN ALL. The burden
    // of proving the clear works sits on veda_smoke_r50i2_crossing_clear.S.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows to phase1_entry

phase1_entry:
    li   x23, 0x0CAFE
    li   a7, 999
    ecall
resume1:
    li   t3, 0x0CAFE
    bne  x23, t3, fail
    csrr t3, 0x7c0
    la   t4, phase1_entry
    bne  t3, t4, fail
    csrr t3, 0x7c1
    li   t4, 0x0044                       # matches the real, objdump-confirmed populate Length above
    bne  t3, t4, fail
    li   x21, 0x600D                      # Phase 1: canary+CSR-readback passed

    nop
    j    fail                             # deliberate escape -- must hard-trap if bounds real

.balign 4
phase2_setup:
    # ============================== PHASE 2 ==============================
    la   t0, phase2_entry
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 143
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # -- CODE_2

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT since R75/R76, so an object is no
    // longer public by accident: R75 bound another domain's CODE object by name
    // and installed that domain's identity in three instructions, and R75b did
    // the same through a TYPE AUTHORITY. Objects a compartment must bind are now
    // DECLARED, next to where they are created. Region 0 is this file's flat
    // layout showing through -- DESIGN_07 records principal granularity as the
    // open question that no declaration can settle.
    li   x2, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 144
    li   x2, 0x8003000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # -- DATA_2

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT since R75/R76, so an object is no
    // longer public by accident: R75 bound another domain's CODE object by name
    // and installed that domain's identity in three instructions, and R75b did
    // the same through a TYPE AUTHORITY. Objects a compartment must bind are now
    // DECLARED, next to where they are created. Region 0 is this file's flat
    // layout showing through -- DESIGN_07 records principal granularity as the
    // open question that no declaration can settle.
    li   x2, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    li   x1, 140
    .insn i 0x0b, 0x5, x2, x1, 0
    li   x1, 143
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 144
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2

    li   x30, 2
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows to phase2_entry

phase2_entry:
    li   a7, 999
    ecall
resume2:
    csrr t3, 0x7c0
    bnez t3, fail                          # must be 0 (unbounded), not phase2_entry
    csrr t3, 0x7c1
    li   t4, 0xFFFFFFFFFF                  # RTL-3: Length is 40 bits, so the UNBOUNDED
                                           # sentinel is 0xFFFFFFFFFF, not the old 0xFFFF
    bne  t3, t4, fail
    li   x25, 0x600D                       # Phase 2: explicit override honored

.balign 4
phase3_setup:
    # ============================== PHASE 3 ==============================
    la   t0, phase3_entry
    slli t0, t0, 32
    li   t1, 0x004C0402                   # Length=0x004C (76B) -- exact byte budget through
                                          # resume3's own CSR-readback checks AND the exit
                                          # ecall that leaves the compartment (objdump-verified:
                                          # the exit ecall's own last byte sits at offset 0x4B,
                                          # fail: starts exactly at offset 0x4C, the first byte
                                          # genuinely outside this bound). Was 0x0048 before
                                          # RTL-3: resume3's UNBOUNDED compare constant grew
                                          # from a 2-instruction li 0xFFFF to a 3-instruction
                                          # li 0xFFFFFFFFFF, so the same code is 4 bytes longer.
    or   t0, t0, t1
    li   x1, 145
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # -- CODE_3

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT since R75/R76, so an object is no
    // longer public by accident: R75 bound another domain's CODE object by name
    // and installed that domain's identity in three instructions, and R75b did
    // the same through a TYPE AUTHORITY. Objects a compartment must bind are now
    // DECLARED, next to where they are created. Region 0 is this file's flat
    // layout showing through -- DESIGN_07 records principal granularity as the
    // open question that no declaration can settle.
    li   x2, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 146
    li   x2, 0x8004000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # -- DATA_3

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT since R75/R76, so an object is no
    // longer public by accident: R75 bound another domain's CODE object by name
    // and installed that domain's identity in three instructions, and R75b did
    // the same through a TYPE AUTHORITY. Objects a compartment must bind are now
    // DECLARED, next to where they are created. Region 0 is this file's flat
    // layout showing through -- DESIGN_07 records principal granularity as the
    // open question that no declaration can settle.
    li   x2, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    li   x1, 140
    .insn i 0x0b, 0x5, x2, x1, 0
    li   x1, 145
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 146
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2

    li   x30, 3
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows to phase3_entry

phase3_entry:
    li   a7, 999
    ecall                                  # OUTER ecall -- x30 still 3 when this fires
resume3:
    csrr t3, 0x7c0
    la   t4, phase3_entry
    bne  t3, t4, fail                      # must be phase3_entry, NOT corrupted by the nested trap
    csrr t3, 0x7c1
    li   t4, 0x004C                        # matches the real, objdump-confirmed populate Length above
    bne  t3, t4, fail
    csrr t3, 0x7c3                         # mepcc_length must now be self-consumed (UNBOUNDED)
    li   t4, 0xFFFFFFFFFF                  # RTL-3: 40-bit Length field -- UNBOUNDED sentinel
    bne  t3, t4, fail
    li   x26, 0x600D                       # Phase 3: nested-trap staleness + repeatability, all correct

    # -- all_done/fail live outside phase3_entry's own narrow bounds --
    #    a raw `j all_done` here would itself be an (unintended) out-of-
    #    bounds fetch, found the same way as everything else in this
    #    file: --trace-instr. Exit the compartment the same way Phase 1
    #    already does, via a real ecall-mediated trap (x30=5), not a raw
    #    jump. --
    li   x30, 5
    li   a7, 999
    ecall

fail:
    li   x22, 0xDEAD

all_done:
1:
    j 1b

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 11
    beq  t3, t4, h_ecall
    # -- any non-ecall trap during Phase 1 (x30==1) is Phase 1's OWN
    #    deliberate escape (the nop; j fail after the CSR-readback check)
    #    -- confirm it's genuinely the expected PCC-bounds violation, then
    #    continue on to Phase 2 rather than falling into the shared fail:
    #    (which is reserved for real, unexpected failures). --
    li   t4, 1
    bne  x30, t4, fail
    j    h_phase1_escape

h_ecall:
    li   t4, 1
    beq  x30, t4, h_phase1                # Phase 1: touch NEITHER pcc_* NOR mepcc_* -- pure automatic restore
    li   t4, 2
    beq  x30, t4, h_phase2                # Phase 2: explicit override
    li   t4, 3
    beq  x30, t4, h_phase3_outer          # Phase 3 outer: trigger a nested trap before its own mret
    li   t4, 4
    beq  x30, t4, h_phase3_inner          # Phase 3 inner (nested): trivial, touches nothing PCC-related
    li   t4, 5
    beq  x30, t4, h_phase3_exit           # Phase 3's own ecall-mediated exit into the shared epilogue
    j    fail

h_phase1:
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase1_escape:
    # -- confirm this is genuinely the expected PCC-bounds violation
    #    (cap_idx=16, cause=0x01 -> mtval=0x201), the real proof Phase 1's
    #    restored bounds are actually enforced, not merely CSR-readable --
    #    then redirect execution to phase2_setup. Real bug found via
    #    --trace-instr while debugging this exact file: this trap's own
    #    capture re-populates veda_mepcc_* with phase1's real bounds
    #    (PCC was still narrowed to them at the moment of THIS trap) --
    #    without an explicit clear here, the mret below would auto-
    #    restore those stale bounds right as it redirects to phase2_setup
    #    (a completely different address, outside them), causing an
    #    immediate, wrong fetch-bounds trap. This IS the real "leaving
    #    the compartment for good" case -- the identical explicit-clear
    #    fix already applied to the 4 pre-existing regression tests. --
    csrr t3, mtval
    li   t4, 0x201
    bne  t3, t4, fail
    li   t3, 0xFFFFFFFFFF                 # RTL-3: 40-bit Length -- UNBOUNDED is 0xFFFFFFFFFF
    csrw 0x7c3, t3                        # veda_mepcc_length := unbounded
    la   t3, phase2_setup
    csrw mepc, t3
    mret

h_phase2:
    # R12 REWRITE. Software may still influence WHAT is restored -- it may
    # not influence WHETHER a restore happens.
    #
    # This handler used to write only mepcc_length, relying on the in-band
    # sentinel to SUPPRESS the restore entirely, so that PCC stayed at the
    # trap-reset {0, UNBOUNDED}. That mechanism is gone: occupancy is now
    # carried out of band by the trap depth, so the restore fires whenever a
    # frame is genuinely owed, regardless of any value software writes.
    #
    # The intent -- resume unbounded -- is still fully expressible, and now
    # it is expressed honestly: write BOTH halves of the frame that is going
    # to be restored. This grants software no authority it did not already
    # have, since anything able to write 0x7C2/0x7C3 while unbounded can
    # already write PCC directly via 0x7C0/0x7C1.
    li   t3, 0
    csrw 0x7c2, t3                        # mepcc_base  := 0
    li   t3, 0xFFFFFFFFFF                 # 40-bit Length; UNBOUNDED is 0xFFFFFFFFFF
    csrw 0x7c3, t3                        # mepcc_length := UNBOUNDED
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase3_outer:
    # -- save the OUTER's own real mepc (the outer ecall's own address)
    #    into a scratch GPR BEFORE triggering the nested ecall. Real bug
    #    found via --trace-instr: mepc, exactly like mepcc, is a single,
    #    global CSR the hardware captures UNCONDITIONALLY on every trap
    #    (no conditional guard, unlike mepcc's own new one) -- the
    #    NESTED trap silently overwrites it with ITS OWN fault address,
    #    and h_phase3_inner's own mepc+4 bookkeeping (for its own
    #    correct resume) leaves it holding THAT value permanently. If
    #    this code re-read the CSR later (assuming it still held the
    #    OUTER's own original ecall address), it would compute a
    #    completely wrong resume target. Saved here, before it can be
    #    clobbered. --
    csrr s2, mepc
    # R36: mstatus joins mepc in this save, and for the identical reason stated
    # directly above -- it is a single, global CSR the hardware rewrites on every
    # trap, and the nested episode consumes it. Specifically: the inner mret sets
    # MPP to the LEAST-privileged supported mode, which is what the privileged
    # spec requires, so by the time the OUTER mret runs, MPP reads User and this
    # handler would return to User instead of Machine. Without this save, resume3
    # below executes its CSR read-backs unprivileged and takes an
    # Illegal_Instruction it never asked for.
    #
    # WHY THIS IS SOFTWARE'S JOB HERE, when h_phase3_inner's own comment argues
    # the opposite for mepcc and that argument is right. The two are different
    # kinds of state. A stale mepcc restores BOUNDS, and getting those wrong can
    # hand back authority that was never held -- so R12 made the hardware track
    # it by depth and poison it, because only hardware can be trusted with a
    # thing that escalates. A stale MPP can only ever restore LESS privilege
    # than was held, because the spec pins the post-mret value to the least
    # privileged mode; the failure direction is de-escalation, which is
    # fail-safe. Hardware tracks what can escalate. Software saves what can only
    # de-escalate. Inventing a depth-tracked MPP here would be non-standard
    # hardware solving a problem the specification already made safe -- and it
    # would put this layer back in exactly the position R36 exists to get it out
    # of, implementing privilege behaviour the model does not define.
    csrr s3, mstatus
    li   x30, 4                           # mark: the NEXT ecall trap is the nested one
    li   a7, 999
    ecall                                  # nested trap fires HERE, from M-mode (unbounded PCC)
    # -- resumed here via the nested trap's own mret. Second real design
    #    point: the conditional-capture guard already correctly stops
    #    the NESTED trap from re-capturing mepcc (PCC was already
    #    unbounded at its own trap-time) -- phase3's real bounds
    #    genuinely survive, untouched, in mepcc across the whole nested
    #    episode (s0/s1 below). But mepcc is a single, global pair -- it
    #    cannot by itself distinguish "the OUTER's own eventual real
    #    mret, which SHOULD auto-restore" from "the INNER's own mret,
    #    which should NOT" (both see the identical mepcc_length !=
    #    UNBOUNDED condition). h_phase3_inner therefore explicitly hides
    #    mepcc (saves it into s0/s1, clears it) before its own mret, and
    #    this code restores it here, right before the OUTER's own real
    #    mret -- genuine, necessary software cooperation around a
    #    reentrant trap window, the same discipline any real OS kernel
    #    needs for nested-trap safety, not a workaround. --
    # R12: nothing to restore -- h_phase3_inner no longer hides mepcc,
    # because the hardware now distinguishes an inner unwind from the
    # outermost one by depth rather than by a value comparison. The outer
    # frame has simply been sitting untouched across the whole nested
    # episode, which is the property this phase now asserts.
    li   x30, 3                           # restore phase marker for correctness/clarity (not re-checked)
    csrw mstatus, s3                      # R36: put MPP back the way this frame found it
    addi t3, s2, 4                        # the OUTER's own real resume address (s2, not a re-read CSR)
    csrw mepc, t3
    mret

h_phase3_inner:
    # -- save mepcc (still holding phase3's real bounds, untouched by
    #    the conditional-capture guard) into s0/s1 -- callee-saved by
    #    convention, guaranteed to survive this mret/resume round trip
    #    unmodified (mret never touches GPRs) -- then clear mepcc so
    #    THIS mret does not itself auto-restore (that would land at the
    #    wrong address, right after the nested ecall, under the wrong,
    #    still-narrow bounds). h_phase3_outer's own continuation above
    #    restores mepcc from s0/s1 before its own, real, intended
    #    restore-triggering mret. --
    # R12 REWRITE -- the hide/clear/restore dance is DELETED.
    #
    # This handler used to save mepcc into s0/s1 and clear it, so that its
    # own mret would not consume the OUTER's saved frame. That was correct
    # software cooperation around a real hardware limitation, and the
    # comment above states the limitation exactly: mepcc alone "cannot by
    # itself distinguish the OUTER's own eventual real mret from the
    # INNER's own mret -- both see the identical mepcc_length != UNBOUNDED
    # condition."
    #
    # R12 removes that limitation IN HARDWARE. Occupancy is carried out of
    # band by the trap depth, so an inner unwind and the outermost unwind
    # are now distinguishable by construction: the inner one reconstructs
    # the reset context and leaves the saved frame alone, and only the
    # outermost one consumes it.
    #
    # Deleting this is the point of the rewrite, not a simplification of
    # it. Leaving software to hide a frame the hardware can now track would
    # keep a security-relevant invariant resting on handler discipline --
    # exactly what a hardware-native design exists to avoid. If this dance
    # is ever needed again, the depth mechanism has regressed.
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase3_exit:
    # -- all sentinels (x21/x25/x26) are already correct at this point;
    #    this ecall exists purely to leave phase3_entry's own narrow
    #    compartment via the same trap-mediated mechanism h_phase1_escape
    #    already uses, since a raw `j all_done` from inside a still-
    #    narrow compartment is itself an out-of-bounds fetch. mepcc
    #    still holds phase3's own real bounds (this handler touches
    #    neither pcc_* nor mepcc_* before now), so the same explicit
    #    clear is required before redirecting mret to all_done: --
    #    otherwise auto-restore would re-narrow PCC right back down to
    #    phase3_entry, and the fetch of all_done: itself (outside those
    #    bounds) would immediately re-trap. --
    li   t3, 0xFFFFFFFFFF                 # RTL-3: 40-bit Length -- UNBOUNDED is 0xFFFFFFFFFF
    csrw 0x7c3, t3                        # veda_mepcc_length := unbounded
    la   t3, all_done
    csrw mepc, t3
    mret

.section .data
.align 3
dummy_type_authority:
    .dword 0
    .dword 0
