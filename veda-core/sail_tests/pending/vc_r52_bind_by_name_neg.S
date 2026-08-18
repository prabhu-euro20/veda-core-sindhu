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
    #
    # ═══ R52 -- A NAME IS STILL FULL AUTHORITY, AND THAT MAKES R50's FIX
    #     THEATRE ═══════════════════════════════════════════════════════════
    #
    # R50 measured that the capability register file crosses a compartment
    # boundary intact. The obvious fix is to clear it at the crossing. THAT FIX
    # WOULD ACHIEVE NOTHING, and this file is why.
    #
    # The caller here does MORE than any such fix would do for it: it unbinds
    # its own capability register BEFORE crossing. The callee still reads the
    # caller's private object -- because it does not need the register. It needs
    # the NAME, and an Object_ID is a small integer it can guess or enumerate.
    #
    # veda_bind_domain_ok has three arms and two of them are fail-open:
    #     owner_domain == VEDA_DOMAIN_ANY        -> true   <-- every Populate writes ANY
    #     veda_pcc_object == VEDA_OBJECT_NONE    -> true   <-- the ambient context (R34)
    #     otherwise: owner_domain == current domain
    # so the gate only ever bites on an object somebody deliberately narrowed.
    #
    # THE MECHANISM IS SOUND -- PART C proves it. What was never decided is the
    # POLICY, and the odt_entry comment says so in as many words: "mechanism
    # first, policy second." R17 was retracted for making compartments one-way
    # with a blanket cross-domain rule, and its retraction already named the
    # replacement: per-object policy plus an ODT field-write path. That path was
    # built. The policy was not.
    #
    # ═══ UPDATE: THE POLICY LANDED, AND THIS FILE IS STILL RED ON PURPOSE ═══
    # Objects created inside a compartment now belong to that compartment's
    # domain (see vc_r52_creation_domain.S, which demonstrates a region-1
    # compartment's object being refused to a region-0 one while an
    # ambient-created object still binds -- R17's return path intact).
    #
    # This file stays red because BOTH of its compartments are in REGION 0, and
    # the gate compares owner_domain against veda_pcc_object[43 .. 24] -- the
    # REGION. Two compartments in one region are ONE DOMAIN by design: R10 makes
    # the region field of a code capability's Object_ID the unforgeable domain
    # identity. So the machine is behaving exactly as specified here.
    #
    # What this file now waits on is re-graining the gate's SUBJECT from region
    # to object, which needs a field wider than owner_domain's 20 bits to hold a
    # 44-bit identity. That is a separate decision, and it is not the creation
    # default this finding was originally about.
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
    # ═══ PART A -- the caller's private object, and it hands over NOTHING ═══
    li   a1, 121
    .insn i 0x0b, 0x5, x10, a1, 0          # veda.bind c10, 121
    li   t1, 0
    li   t2, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, t2, x10, t1   # ocs.d c10, t1, t2   -- the secret

    # CONTROL 1: the caller can read its own object back. Without this, a
    # machine on which nothing ever worked would satisfy PART B's refusal for
    # the wrong reason.
    li   t3, 0
    .insn r 0x0b, 0x3, 0x00, t3, x10, t1   # ocl.d t3, t1, c10
    li   t4, 0xC0FFEE
    bne  t3, t4, check_fail
    li   s5, 0x600D

    # The caller does MORE than any register-clearing crossing would do for it:
    # it untags its own capability register before calling.
    li   a1, 999
    .insn i 0x0b, 0x5, x10, a1, 1          # veda.bind.notrap c10, 999 -> untagged

    .insn r 0x5b, 0x1, 0x12, x0, x8, x9    # ocinvoke c8, c9

.balign 4
callee_entry:
    # ═══ PART B -- the callee needs only the NUMBER ════════════════════════
    # Nothing was inherited. 121 is a constant in this instruction stream.
    li   s2, 0
    li   s6, 0
    li   a1, 121
    .insn i 0x0b, 0x5, x11, a1, 0          # veda.bind c11, 121
    li   t1, 0
    .insn r 0x0b, 0x3, 0x00, s6, x11, t1   # ocl.d s6, t1, c11
    mv   s2, s0                            # traps taken by the callee

    # CONTROL 2 -- the callee's own legitimate work still runs, so a machine
    # that simply trapped everything after a crossing cannot pass PART B.
    li   t2, 0x1234
    li   t1, 0
    .insn r 0x0b, 0x3, 0x01, t2, x15, t1   # ocs.d c15, t1, t2
    li   s7, 0
    .insn r 0x0b, 0x3, 0x00, s7, x15, t1   # ocl.d s7, t1, c15
    li   x25, 1
    ecall

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 8
    beq  t3, t4, verdict
    li   t4, 11
    beq  t3, t4, verdict
    addi s0, s0, 1
    mv   s1, t3
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.balign 4
verdict:
    # PART C is the control that decides what the finding IS. It lives in the
    # sibling file vc_r52_bind_domain_default_ctl.S: with veda.odt.set.domain
    # giving object 121 a real owner_domain, the identical PART B takes 2 traps
    # and reads 0. The gate works. The default is what is open.
    li   t4, 0x600D
    bne  s5, t4, check_fail                # CONTROL 1: the caller's own access worked
    li   t4, 0x1234
    bne  s7, t4, check_fail                # CONTROL 2: the callee's own access worked

    # THE ASSERTIONS THIS FILE OWES ONCE THE POLICY IS TAKEN:
    bne  s2, x0, 1f                        # the callee's bind must trap
    j    check_fail
1:
    bne  s6, x0, check_fail                # and must read NOTHING
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 64
win:
    .space 64
