.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R48 -- DOES A CALLEE COMPARTMENT INHERIT THE CALLER'S ODA?
    #
    # OCInvoke narrows PCC to the callee's bounds, installs a fresh IDC,
    # reloads the CRBR for the entered domain, and CLEARS the SSC. Every
    # authority the crossing touches is narrowed or dropped -- except the ODA
    # and the TSC, which the source states are "untouched by OCInvoke".
    #
    # The codebase already wrote the argument against that, for the SSC, in the
    # OCInvoke clause itself: "applying ODA/TSC's own 'untouched by OCInvoke'
    # convention to SSC would have left the caller's entire stack region
    # reachable from the callee." It was never applied to the ODA or the TSC.
    #
    # BEFORE R47 THIS WAS ACADEMIC -- the ODA had no window, so everything was
    # already reachable. R47 gave it one. So the question this test answers is
    # now sharp: does a callee inherit MINT AUTHORITY OVER THE CALLER'S WINDOW?
    #
    # AND THE CALLER CANNOT DEFEND ITSELF. VEDA_OSPECIALRW is Machine-only for
    # read AND write of all three SCRs (veda_cap_insts.sail's own privilege
    # gate; RTL $veda_ospecialrw_violation = $is_veda_ospecialrw && !$priv), so
    # a User-mode caller holding a delegated ODA has NO INSTRUCTION with which
    # to drop it before calling. There is no software discipline available;
    # if this is to be closed, hardware must close it.
    #
    # OBJECT_ID CHOICE, and it cost a debugging cycle. The first draft used
    # 50..56. Object_ID 55 is a SEEDED FIXTURE (veda_regs.sail's
    # veda_test_seed_odt), so the caller's own in-window mint was refused --
    # by R47's OLD-window check, correctly: a delegated actor may not
    # repopulate a slot whose current contents lie outside its window. Before
    # R47 that same instruction would have SILENTLY OVERWRITTEN a fixture.
    # Third instance of this project's Object_ID-collision class; the fixture
    # now lives at 120..106, which nothing seeds.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0                      # trap count
    li   s1, 0                      # cause of the most recent trap

    # ─── M-mode: the authority, scoped to `win` ───────────────────────────
    # object 120: Base = win, Length = 64, Perms = 0x0080 (PERM_ACCESS_SYSTEM_REGISTERS)
    la   t0, win
    slli t0, t0, 32
    li   t1, (64 << 16) | 0x0080
    or   a2, t0, t1
    li   a1, 120
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 120

    # object 121: THE VICTIM. The caller's own object, INSIDE the caller's
    # ODA window -- Base = win, Length = 32, Perms = LOAD|STORE.
    la   t0, win
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 121
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 121

    # ─── M-mode: the compartment fixture (the established pattern) ────────
    la   t0, callee_entry
    slli t0, t0, 32
    li   t1, 0x00400402                     # Length 0x40, Perms EXECUTE|INVOKE
    or   a2, t0, t1
    li   a1, 122
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # CODE

    li   a1, 123
    li   a2, 0x800107000040040C             # DATA  Perms LOAD|STORE|INVOKE
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2

    li   a1, 124
    li   a2, 0x8001080000400300             # type authority  Perms SEAL|UNSEAL
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2

    li   a1, 120
    .insn i 0x0b, 0x5, x1, a1, 0            # veda.bind c1, 120   (the authority)
    li   a1, 122
    .insn i 0x0b, 0x5, x5, a1, 0            # veda.bind c5, 122   (code)
    li   a1, 123
    .insn i 0x0b, 0x5, x6, a1, 0            # veda.bind c6, 123   (data)
    li   a1, 124
    .insn i 0x0b, 0x5, x7, a1, 0            # veda.bind c7, 124   (type authority)
    .insn r 0x5b, 0x1, 0x10, x8, x5, x7     # cseal c8, c5, c7   (sealed code)
    .insn r 0x5b, 0x1, 0x10, x9, x6, x7     # cseal c9, c6, c7   (sealed data)

    .insn r 0x5b, 0x1, 0x13, x2, x1, x0     # ospecialrw c2, ODA, c1  -- ODA := c1

    # ─── drop to User the architected way (R36) ───────────────────────────
    la   t0, u_caller
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0
    mret

.balign 4
u_caller:
    # ═══ CONTROL A -- the victim is alive before the crossing ═════════════
    li   a1, 121
    .insn i 0x0b, 0x5, x10, a1, 1           # veda.bind.notrap c10, 121
    .insn r 0x5b, 0x0, 0x03, t3, x10, x0    # cgettag t3, c10
    li   t4, 1
    bne  t3, t4, check_fail

    # ═══ CONTROL B -- the CALLER's own delegated authority genuinely works.
    # It mints object 125 inside its own window. This word is what separates
    # "the callee was refused" from "the ODA was destroyed for everyone", and
    # it is checked AGAIN after the return below.
    la   t0, win
    addi t0, t0, 32
    slli t0, t0, 32
    li   t1, (16 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 125
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 125 -- MUST SUCCEED
    bne  s0, x0, check_fail

    # ═══ the crossing ════════════════════════════════════════════════════
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9     # ocinvoke c8, c9

.balign 4
callee_entry:
    # ---- narrowed PCC, still User, a DIFFERENT compartment ----
    # Note: no ordinary load/store may appear below this line. Milestone 19's
    # purecap rule refuses them unconditionally inside a bounded compartment,
    # which is why every verdict is recorded in registers and asserted after
    # the ecall escape rather than stored here.
    li   s2, 0                              # the callee's own trap ledger

    # ═══ THE ATTACK ══════════════════════════════════════════════════════
    # Destroy object 121 -- the CALLER's object, inside the CALLER's ODA
    # window. The callee was handed a code capability and a data capability
    # and nothing else. If this succeeds, an OCInvoke handed the callee the
    # power to revoke the caller's memory.
    li   a1, 121
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy 121

    # ═══ and the wider half: mint over the caller's window ════════════════
    la   t0, win
    slli t0, t0, 32
    li   t1, (16 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 126
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 126 inside the caller's window

    ecall                                   # escape to M-mode for the verdict

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 8
    beq  t3, t4, verdict                    # E_U_EnvCall -- the escape
    li   t4, 11
    beq  t3, t4, verdict                    # E_M_EnvCall, if the drop ever regresses
    # any other trap: count it, record it, skip the faulting instruction
    addi s0, s0, 1
    mv   s1, t3
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.balign 4
verdict:
    # ---- M-mode again, PCC reset by the trap, ordinary stores legal ----
    #
    # A1. Did the callee DESTROY the caller's object? tag 0 means yes.
    li   a1, 121
    .insn i 0x0b, 0x5, x11, a1, 1           # veda.bind.notrap c11, 121
    .insn r 0x5b, 0x0, 0x03, t3, x11, x0    # cgettag t3, c11
    li   t4, 1
    bne  t3, t4, check_fail                 # <- FAILS TODAY: the callee killed it

    # A2. Did the callee MINT over the caller's window? tag 1 means yes.
    li   a1, 126
    .insn i 0x0b, 0x5, x12, a1, 1           # veda.bind.notrap c12, 126
    .insn r 0x5b, 0x0, 0x03, t3, x12, x0    # cgettag t3, c12
    bne  t3, x0, check_fail                 # <- FAILS TODAY: the mint landed

    # A3. Both attempts must have been REFUSED, not merely ineffective.
    li   t4, 2
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    # ═══ CONTROL C -- object 121 really was destroyable ════════════════════
    # Without this, "51 survived" could mean the machine refuses to destroy it
    # for some unrelated reason, and A1 would prove nothing.
    li   a1, 121
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy 121 from M-mode
    li   a1, 121
    .insn i 0x0b, 0x5, x13, a1, 1
    .insn r 0x5b, 0x0, 0x03, t3, x13, x0
    bne  t3, x0, check_fail                 # really gone now

    # ═══ CONTROL D -- object 125 survived, so the CALLER's pre-crossing mint
    # was real. This is the word that discriminates between the candidate
    # fixes: any fix that CLEARS the ODA at the crossing must still leave the
    # caller's earlier work intact.
    li   a1, 125
    .insn i 0x0b, 0x5, x14, a1, 1
    .insn r 0x5b, 0x0, 0x03, t3, x14, x0
    li   t4, 1
    bne  t3, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 64
win:
    .space 64
