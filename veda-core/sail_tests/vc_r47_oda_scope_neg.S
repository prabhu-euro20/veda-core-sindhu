.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R47 -- THE ODA IS A CAPABILITY WHOSE WINDOW THE MACHINE NEVER READS.
    #
    # veda_oda_authorized() is three terms wide:
    #     veda_oda_tag & not(isSealedCap(veda_oda)) & permBit(Perms, PERM_ASR)
    # Tag, otype, one permission bit. Base, Length, Offset and Object_ID --
    # 196 of the capability's 256 bits -- are never consulted by any of the
    # SEVEN instructions this predicate authorizes.
    #
    # So the delegated authority to write the Object Descriptor Table is a
    # BEARER TOKEN over ALL of memory: whoever holds any ODA may mint a
    # descriptor naming any Base, any Length and any Perms, then Bind it and
    # dereference it. That is the whole memory-safety claim, delegated away
    # by a capability that was made a capability precisely so it could carry
    # a window (veda_regs.sail: the ODA "must carry Base/Length/Perms/Tag,
    # none of which a 64-bit CSR can hold").
    #
    # MEASURED, NOT DERIVED -- and the measurement was already in the suite.
    # rtl/sim/veda_smoke_m11.S mints authority object 40 at Base 0x80011000
    # Length 0x40, installs it as the ODA, drops to User, and from User mints
    # object 41 at Base 0x80012000 -- FOUR KILOBYTES OUTSIDE its own
    # authority's window -- with Perms 0x0300. That test passes, and its own
    # comment calls it "the real proof" the ODA path works. It does prove
    # that. It also demonstrates the escape, and pinned it as the contract.
    #
    # THE RULE ADOPTED HERE, uniform across all seven ODA-gated instructions:
    #
    #   On the DELEGATED path only, the memory a descriptor names -- what the
    #   entry names now, AND what it will name after -- must lie inside the
    #   ODA's own window. Machine privilege is untouched: it needs no ODA and
    #   already owns the machine, so scoping it would be theatre.
    #
    # Refusal is Illegal_Instruction, matching all seven sibling refusals on
    # these same instructions, AND deliberately: a distinct cause code would
    # let unprivileged code binary-search its own ODA's window by trap cause.
    # DESIGN_07 D-7 is the same oracle shape, found on a different field.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0                      # trap count
    li   s1, 0                      # cause of the most recent trap

    # ─── M-mode: build the authority, and scope it to `win` ───────────────
    # object 40: Base = win, Length = 64, Perms = 0x0080 (PERM_ACCESS_SYSTEM_REGISTERS)
    la   t0, win
    slli t0, t0, 32
    li   t1, (64 << 16) | 0x0080
    or   a2, t0, t1
    li   a1, 40
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 40

    li   a1, 40
    .insn i 0x0b, 0x5, x1, a1, 0            # veda.bind c1, 40
    .insn r 0x5b, 0x0, 0x03, t3, x1, x0     # cgettag t3, c1
    li   t4, 1
    bne  t3, t4, check_fail

    .insn r 0x5b, 0x1, 0x13, x2, x1, x0     # ospecialrw c2, c1   -- ODA := c1

    # ─── CONTROL 0: Machine is NOT scoped by the ODA it happens to hold ───
    # Populate object 43 at `out`, which the ODA does not cover. Machine took
    # the `cur_privilege == Machine` half of the OR, so no window applies.
    # Without this control a fix that scoped BOTH halves would pass every
    # negative below while breaking the machine.
    la   t0, out
    slli t0, t0, 32
    li   t1, (64 << 16) | 0x000C            # PERM_LOAD | PERM_STORE
    or   a2, t0, t1
    li   a1, 43
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 43  -- MUST SUCCEED
    bne  s0, x0, check_fail

    li   a1, 43
    .insn i 0x0b, 0x5, x3, a1, 1            # veda.bind.notrap c3, 43
    .insn r 0x5b, 0x0, 0x03, t3, x3, x0     # cgettag t3, c3
    li   t4, 1
    bne  t3, t4, check_fail

    # veda_attr is Machine-only, and ATTACK 3 below needs a saturating Length
    # left in it. Set it HERE: a User-mode populate.fast reads veda_attr as an
    # internal register, not through a CSR instruction, so User can consume a
    # value it could never have written. That is not a defect -- it is exactly
    # why the wrap case is reachable from User at all, and why it is tested.
    li   t0, 0xFFFFFFFFFF
    slli t0, t0, 16
    ori  t0, t0, 0x000C
    csrw 0x7c4, t0

    # ─── drop to User the architected way (R36): MPP = 0b00, then mret ────
    li   t1, 0x1800
    csrc mstatus, t1
    la   t2, umode
    csrw mepc, t2
    mret

umode:
    # ═══ ATTACK 1 -- the escape veda_smoke_m11.S demonstrates ═════════════
    # Mint object 41 at `out`, entirely outside the ODA's window, with
    # PERM_LOAD | PERM_STORE. Before the fix this succeeds and User owns
    # memory its authority never named.
    la   t0, out
    slli t0, t0, 32
    li   t1, (64 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 41
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 41 -- MUST REFUSE
    li   t4, 1
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    # COUNTING A REFUSAL IS NOT CHECKING IT. Assert the EFFECT: object 41 must
    # not exist. bind.notrap soft-fails with tag 0 rather than trapping, so
    # this probe does not perturb the trap ledger.
    li   a1, 41
    .insn i 0x0b, 0x5, x4, a1, 1            # veda.bind.notrap c4, 41
    .insn r 0x5b, 0x0, 0x03, t3, x4, x0     # cgettag t3, c4
    bne  t3, x0, check_fail
    li   t4, 1
    bne  s0, t4, check_fail

    # ═══ CONTROL 1 -- the over-refusal guard, and it is the load-bearing one
    # Mint object 42 INSIDE the window. A machine that simply refused every
    # delegated populate would pass ATTACK 1..5 and fail here.
    la   t0, win
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 42
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 42 -- MUST SUCCEED
    li   t4, 1
    bne  s0, t4, check_fail

    li   a1, 42
    .insn i 0x0b, 0x5, x6, a1, 0            # veda.bind c6, 42
    .insn r 0x5b, 0x0, 0x03, t3, x6, x0     # cgettag t3, c6
    li   t4, 1
    bne  t3, t4, check_fail

    # ═══ ATTACK 2 -- straddle the far edge ════════════════════════════════
    # Base inside the window, Base+Length past its end. Containment is not a
    # membership test on Base.
    la   t0, win
    slli t0, t0, 32
    li   t1, (128 << 16) | 0x000C           # window is 64 bytes
    or   a2, t0, t1
    li   a1, 44
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # MUST REFUSE
    li   t4, 2
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    # ═══ ATTACK 3 -- the R18 shape: make Base+Length WRAP ═════════════════
    # populate.fast takes Length from veda_attr, left saturating by Machine
    # above. Base 0x8000xxxx + Length 0xFFFFFFFFFF exceeds 56 bits, so a
    # containment check computed at the operands' own width wraps and reports
    # the object as CONTAINED. R18 was exactly this bug on the dereference
    # bounds check; the arithmetic here is 57 bits wide for the same reason.
    la   a2, win
    li   a1, 45
    .insn r 0x0b, 0x0, 0x04, x5, a1, a2     # veda.odt.populate.fast 45 -- MUST REFUSE
    li   t4, 3
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    # ═══ ATTACK 4 -- hijack a descriptor that lives outside the window ════
    # Object 43 is Machine's, at `out`. Repopulating it with a Base INSIDE the
    # window satisfies "the new window is covered" -- and would still be an
    # escape: it bumps 43's generation (killing every capability Machine holds
    # to it) and repoints a descriptor User has no authority over. So the rule
    # covers BOTH windows: what the entry names now, and what it will name.
    la   t0, win
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 43
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # MUST REFUSE
    li   t4, 4
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    # ... and 43 must be UNTOUCHED, not merely un-repointed: still at `out`.
    li   a1, 43
    .insn i 0x0b, 0x5, x7, a1, 1            # veda.bind.notrap c7, 43
    .insn r 0x5b, 0x0, 0x03, t3, x7, x0     # cgettag t3, c7
    li   t4, 1
    bne  t3, t4, check_fail
    .insn r 0x5b, 0x0, 0x00, t3, x7, x0     # cgetbase t3, c7
    la   t4, out
    bne  t3, t4, check_fail

    # ═══ ATTACK 5 -- destroy a descriptor outside the window ══════════════
    li   a1, 43
    # NOTE ON THIS ENCODING, because the first draft of this test got it wrong
    # and the mistake is instructive. veda.odt.destroy is R-type
    # (funct7 0000011, funct3 001); an I-type `.insn i 0x0b, 0x1, ..., 0` is
    # not Destroy at all, it is an encoding the architecture never allocated.
    # ATTACK 5 below then "passed" -- refused by R30's undefined-encoding trap,
    # not by R47's scope check -- and the assertion proved nothing. CONTROL 2
    # is what exposed it, by demanding the SAME instruction SUCCEED one line
    # later. Counting a refusal is not checking it.
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy 43 -- MUST REFUSE
    li   t4, 5
    bne  s0, t4, check_fail
    li   t4, 0x02
    bne  s1, t4, check_fail

    li   a1, 43
    .insn i 0x0b, 0x5, x8, a1, 1            # veda.bind.notrap c8, 43
    .insn r 0x5b, 0x0, 0x03, t3, x8, x0     # cgettag t3, c8
    li   t4, 1
    bne  t3, t4, check_fail                 # still alive

    # ═══ CONTROL 2 -- destroy IS allowed inside the window ════════════════
    li   a1, 42
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy 42 -- MUST SUCCEED
    li   t4, 5
    bne  s0, t4, check_fail

    li   a1, 42
    .insn i 0x0b, 0x5, x9, a1, 1            # veda.bind.notrap c9, 42
    .insn r 0x5b, 0x0, 0x03, t3, x9, x0     # cgettag t3, c9
    bne  t3, x0, check_fail                 # really gone

    # ═══ CONTROL 3 -- ordinary unprivileged work still runs ═══════════════
    li   t3, 7
    addi t3, t3, 3
    li   t4, 10
    bne  t3, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi s0, s0, 1
    csrr s1, mcause
    csrr t4, mepc
    addi t4, t4, 4
    csrw mepc, t4
    mret

.section .data
.balign 64
win:
    .space 64
.balign 64
out:
    .space 64
