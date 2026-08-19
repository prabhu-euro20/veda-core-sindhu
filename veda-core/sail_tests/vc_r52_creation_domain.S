.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R52 -- THE CREATION-TIME BINDING POLICY
    #
    #   An object created INSIDE a compartment belongs to that compartment's
    #   domain. An object created in the AMBIENT context stays open.
    #
    # The per-object bind gate has worked since R13. What was never decided was
    # the DEFAULT -- every Populate wrote VEDA_DOMAIN_ANY, so the gate never bit
    # unless software explicitly narrowed an object. Measured consequence: a
    # callee needs only the NAME. Given the integer alone, with the caller
    # having untagged its own capability register first, it re-bound the
    # caller's private object and read it. Zero traps. That also made clearing
    # registers at the crossing (R50) theatre.
    #
    # The deferral was deliberate and the source says so -- the odt_entry
    # comment: "mechanism first, policy second." R17 took a policy once and was
    # RETRACTED THE SAME DAY: it forbade cross-domain Bind outright, and a
    # compartment's RETURN PATH is by construction in another domain, so
    # compartments became one-way and nothing could ever return.
    #
    # THE AMBIENT ARM IS WHAT KEEPS R17 CLOSED, and CONTROL 3 below is what
    # proves it: the boot/loader context's objects -- return paths, type
    # authorities, shared services -- stay ANY and remain bindable from anywhere.
    #
    # REGISTER CHOICE IS NOT INCIDENTAL. c10..c14 are FIXTURE-SEEDED
    # (wC(Vcapno(10..14))), so a cgettag on one of them reads the seed and not
    # the bind -- and a bind that TRAPS never writes its destination at all.
    # Every measurement below uses c0/c1/c2, which nothing seeds. Getting this
    # wrong produced four consecutive vacuous readings before one was sound.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0

    la   t0, arena
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   s9, t0, t1

    # ---- ambient: everything built here is created with NO compartment
    #      active, so it gets VEDA_DOMAIN_ANY and stays shareable ----
    la   t0, compA
    slli t0, t0, 32
    li   t1, 0x02000402                     # Len 0x200, Execute|Invoke
    or   a2, t0, t1
    li   a1, 16777246                       # region-1 CODE  {r=1, l=30}
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 16777247                       # region-1 DATA  {r=1, l=31}
    li   a2, 0x800107000040040C
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    la   t0, compB
    slli t0, t0, 32
    li   t1, 0x02000402
    or   a2, t0, t1
    li   a1, 170                            # region-0 CODE
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 171                            # region-0 DATA
    li   a2, 0x800107000040040C
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2
    li   a1, 172                            # type authority, ambient -> ANY
    li   a2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2

    li   a1, 16777246
    .insn i 0x0b, 0x5, x3, a1, 0
    li   a1, 16777247
    .insn i 0x0b, 0x5, x4, a1, 0
    li   a1, 172
    .insn i 0x0b, 0x5, x7, a1, 0
    .insn r 0x5b, 0x1, 0x10, x8, x3, x7     # sealed region-1 pair
    .insn r 0x5b, 0x1, 0x10, x9, x4, x7
    li   a1, 170
    .insn i 0x0b, 0x5, x5, a1, 0
    li   a1, 171
    .insn i 0x0b, 0x5, x6, a1, 0
    .insn r 0x5b, 0x1, 0x10, x12, x5, x7    # sealed region-0 pair
    .insn r 0x5b, 0x1, 0x10, x13, x6, x7
    bnez s0, check_fail                     # the ambient build may not trap

    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9     # ocinvoke -> A, in REGION 1

.balign 4
compA:
    # Running in region 1. Anything created here now belongs to domain 1.
    li   a1, 16777256                       # {r=1, l=40}
    mv   a2, s9
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2

    # CONTROL 1: A can bind what A created. A policy that simply refused
    # everything after a crossing would fail here.
    li   a1, 16777256
    .insn i 0x0b, 0x5, x0, a1, 0            # veda.bind c0 -- plain, must not trap
    .insn r 0x5b, 0x0, 0x03, s2, x0, x0
    mv   s3, s0                             # traps inside A: must stay 0

    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x12, x13   # ocinvoke -> B, in REGION 0

.balign 4
compB:
    # A different domain. Bind A's object BY NAME -- the whole point.
    #
    # ═══ R73 RE-AIMED, AND THE RE-AIM MAKES THIS FILE STRONGER ═══
    #
    # This block used to make ONE attempt, with Bind-NoTrap, and assert both a
    # cleared tag and exactly one trap. Two things were wrong with that.
    #
    # First, the refusal is now MODE-DEPENDENT (R73): a domain refusal traps for
    # plain Bind and soft-fails for Bind-NoTrap, because choosing mode 0b01 IS
    # the caller's request for an answer instead of a fault. So one attempt can
    # no longer test both halves.
    #
    # Second -- and this is the part worth keeping -- THE OLD TAG ASSERTION
    # COULD NOT FAIL. The bind trapped, a trap leaves rd untouched, and c1 was
    # never bound to anything, so `cgettag c1` read the architectural reset
    # value. It asserted 0 against a register that was already 0 for reasons
    # having nothing to do with the gate. Only the trap count was load-bearing.
    # The quiet form below fixes that by loading a REAL tagged capability first,
    # so a 0 afterwards proves the soft-fail genuinely WROTE the register.
    #
    # THE LOUD FORM -- plain Bind, hard-trap, rd untouched.
    li   a1, 16777256
    .insn i 0x0b, 0x5, x1, a1, 0            # veda.bind c1 -- PLAIN, must trap
    mv   s5, s0                             # exactly one trap, the refusal

    # CONTROL 3 -- R17'S RETURN PATH, and this is the assertion that stops this
    # policy from repeating R17's retraction. An AMBIENT-created object must
    # still bind from inside a compartment, or compartments become one-way.
    # It doubles as the loaded-register precondition for the quiet form below.
    li   a1, 172
    .insn i 0x0b, 0x5, x2, a1, 0
    .insn r 0x5b, 0x0, 0x03, s6, x2, x0     # MUST be 1

    # THE QUIET FORM -- same refusal, mode 0b01, and it must NOT trap. c2 holds
    # the genuine ambient capability asserted one line above, so a cleared tag
    # here is evidence the soft-fail wrote, not evidence that nothing happened.
    li   a1, 16777256
    .insn i 0x0b, 0x5, x2, a1, 1            # veda.bind.notrap c2 -- foreign domain
    .insn r 0x5b, 0x0, 0x03, s4, x2, x0     # MUST be 0 -- the soft-fail WROTE it
    mv   s7, s0                             # MUST still be 1 -- no NEW trap
    ecall

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 8
    beq  t3, t4, verdict
    li   t4, 11
    beq  t3, t4, verdict
    addi s0, s0, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.balign 4
verdict:
    li   t4, 1
    bne  s2, t4, check_fail                 # CONTROL 1: A bound its own object
    bnez s3, check_fail                     # and nothing trapped inside A
    bnez s4, check_fail                     # THE FINDING: B was refused
    li   t4, 1
    bne  s5, t4, check_fail                 # exactly one trap, the LOUD refusal
    li   t4, 1
    bne  s7, t4, check_fail                 # R73: the QUIET refusal added none
    li   t4, 1
    bne  s6, t4, check_fail                 # CONTROL 3: the ambient object still binds
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.section .data
.balign 32
arena:
    .space 32
