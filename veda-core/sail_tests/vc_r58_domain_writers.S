.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R58 -- THE TWO owner_domain WRITERS THE R52 LANDING GOT WRONG, AND WHY
    #        108/108 DID NOT NOTICE
    #
    # R52's edit was applied by a script that replaced "the first two
    # occurrences" of `owner_domain = VEDA_DOMAIN_ANY`. In file order the three
    # creation/destroy sites are Populate, DESTROY, Populate-Fast -- so it hit
    # Populate (right) and DESTROY (wrong), and missed Populate-Fast entirely.
    #
    #   (1) DESTROY inherited the destroyer's domain, breaking R41, whose whole
    #       point is that the previous occupant's policy has no claim.
    #   (2) POPULATE-FAST still wrote ANY -- and the shipped C allocator uses
    #       exactly that encoding, so R52 was VOID FOR EVERY HEAP OBJECT while
    #       being reported closed.
    #
    # Both suites stayed green throughout, because nothing checked either. This
    # file is what checks them, and the observable is subtle enough to be worth
    # stating: veda_bind_domain_ok is evaluated BEFORE e.valid, so binding a
    # DESTROYED slot still consults its owner_domain, and the trap CAUSE reports
    # which way it went:
    #       owner_domain reset to ANY  ->  gate passes  ->  OBJECT_NOT_FOUND 0x05
    #       owner_domain left as N     ->  gate fails   ->  DOMAIN_VIOLATION 0x0B
    # A destroyed slot that still names its owner is also an ORACLE for that
    # owner -- the R44 refusal-cause class -- which is the second reason ANY is
    # the right value.
    #
    # Registers: c10..c14 are FIXTURE-SEEDED and a trapping bind never writes its
    # destination, so every reading here uses c0/c1/c2 and asserts trap counts.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0
    li   s1, 0

    la   t0, arena
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   s9, t0, t1

    # ---- ambient build: region-1 compartment A, region-0 compartment B ----
    # A's window is deliberately TIGHT (0x40, not 0x200), and the first draft
    # got this wrong in an instructive way. With 0x200 the window ran from
    # compA to compA+0x200, which SWALLOWED `arena` in .data -- and R45's
    # memory-scoped executing pin then correctly refused to populate an object
    # whose window overlaps the code the compartment is running. The pin was
    # working; the scaffold was wrong. 0x40 covers A's body and stops short of
    # .data. (Its sibling constraint is R51's: the window must still reach the
    # compartment's LAST instruction, here the ocinvoke into B.)
    la   t0, compA
    slli t0, t0, 32
    # R50 increment 2 widened this from 0x40 to 0x80, and the reason is a real
    # cost of that design rather than a scaffold detail: the retain mask is
    # SELF-CONSUMING, so a compartment that wants to pass capabilities onward
    # must set the CSR ITSELF, inside its own PCC window. Two instructions of
    # compartment code per outbound crossing.
    li   t1, 0x00800402
    or   a2, t0, t1
    li   a1, 16777276                       # region-1 CODE {r=1,l=60}
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 16777277                       # region-1 DATA {r=1,l=61}
    li   a2, 0x800107000040040C
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    la   t0, compB
    slli t0, t0, 32
    li   t1, 0x02000402
    or   a2, t0, t1
    li   a1, 200
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 201
    li   a2, 0x800107000040040C
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 202                            # type authority, ambient -> ANY
    li   a2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2

    li   a1, 16777276
    .insn i 0x0b, 0x5, x3, a1, 0
    li   a1, 16777277
    .insn i 0x0b, 0x5, x4, a1, 0
    li   a1, 202
    .insn i 0x0b, 0x5, x7, a1, 0
    .insn r 0x5b, 0x1, 0x10, x8, x3, x7
    .insn r 0x5b, 0x1, 0x10, x9, x4, x7
    li   a1, 200
    .insn i 0x0b, 0x5, x5, a1, 0
    li   a1, 201
    .insn i 0x0b, 0x5, x6, a1, 0
    .insn r 0x5b, 0x1, 0x10, x12, x5, x7
    .insn r 0x5b, 0x1, 0x10, x13, x6, x7
    bnez s0, check_fail

    # veda_attr for the populate.fast below: Length 32, Perms Load|Store
    li   t0, 32
    slli t0, t0, 16
    ori  t0, t0, 0x000C
    csrw 0x7c4, t0

    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9     # -> compartment A, region 1

.balign 4
compA:
    # (1) a POPULATE-FAST object, the encoding the shipped allocator uses
    la   a2, arena
    li   a1, 16777286                       # {r=1, l=70}
    .insn r 0x0b, 0x0, 0x04, x5, a1, a2     # veda.odt.populate.fast
    # (2) a plain-Populate object, destroyed immediately
    li   a1, 16777287                       # {r=1, l=71}
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 16777287
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy
    mv   s3, s0                             # traps inside A: must be 0
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x12, x13   # -> compartment B, region 0

.balign 4
compB:
    # ═══ (1) POPULATE-FAST must have taken A's domain ═════════════════════
    li   a1, 16777286
    .insn i 0x0b, 0x5, x0, a1, 1            # veda.bind.notrap c0
    .insn r 0x5b, 0x0, 0x03, s4, x0, x0     # tag MUST be 0
    mv   s5, s0                             # one trap so far
    mv   s7, s1                             # its mtval

    # ═══ (2) DESTROY must have reset the domain to ANY ════════════════════
    # A destroyed slot's cause discriminates: OBJECT_NOT_FOUND (0x05) if the
    # domain was reset, DOMAIN_VIOLATION (0x0B) if it still names A.
    # PLAIN Bind, not .notrap, and the distinction is the whole discriminator.
    # Under .notrap a not-found object SOFT-FAILS with no trap, so the cause --
    # the only thing that says which way owner_domain went -- never exists. A
    # plain Bind hard-traps on BOTH paths, and the CAUSE separates them:
    #     domain reset to ANY -> gate passes -> OBJECT_NOT_FOUND 0x05
    #     domain still A      -> gate fails  -> DOMAIN_VIOLATION  0x0B
    li   a1, 16777287
    .insn i 0x0b, 0x5, x1, a1, 0            # veda.bind c1 -- PLAIN
    mv   s6, s1                             # its mtval
    mv   s8, s0

    # ═══ CONTROL: an AMBIENT object still binds from here -- R17's return
    # path, and the word that stops a blanket refusal from passing this file.
    li   a1, 202
    .insn i 0x0b, 0x5, x2, a1, 1
    .insn r 0x5b, 0x0, 0x03, s2, x2, x0     # MUST be 1
    ecall

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 8
    beq  t3, t4, verdict
    li   t4, 11
    beq  t3, t4, verdict
    addi s0, s0, 1
    csrr s1, mtval
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.balign 4
verdict:
    bnez s3, check_fail                     # nothing trapped inside A
    bnez s4, check_fail                     # (1) the populate.fast object was REFUSED
    li   t4, 1
    bne  s5, t4, check_fail                 # exactly one trap for it
    andi t4, s7, 0x1f
    li   t3, 0x0b
    bne  t4, t3, check_fail                 # and the cause was DOMAIN_VIOLATION
    li   t4, 2
    bne  s8, t4, check_fail                 # (2) the destroyed slot trapped too
    andi t4, s6, 0x1f
    li   t3, 0x05
    bne  t4, t3, check_fail                 # OBJECT_NOT_FOUND -- the domain WAS reset
    li   t4, 1
    bne  s2, t4, check_fail                 # CONTROL: the ambient object still binds
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
arena:
    .space 32
