.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # ═══════════════════════════════════════════════════════════════════════
    # R59 -- A RE-MINTED OBJECT INHERITED THE PREVIOUS OCCUPANT'S OWNER
    #
    # Sail resets owner_hart = VEDA_OWNER_UNOWNED on Populate, Populate-Fast AND
    # Destroy. The RTL's ONLY dynamic write to the owner byte was the owner
    # CLAIM -- it never reset. So on the hardware a slot's owner survived Destroy
    # and re-Populate, and a fresh object was born owned by whoever last held the
    # slot.
    #
    # BENIGN ON ONE HART AND PERMANENT ON MORE THAN ONE: with MHARTID = 0 a
    # stale 0x00 still passes owner_ok, so nothing shows. With a real second hart
    # the byte can never be cleared -- NO INSTRUCTION IN THE ISA WRITES IT except
    # the claim -- so hart A could never reclaim a slot hart B once bound, even
    # after destroying and re-minting it.
    #
    # This is R41's class applied to the THIRD carried field. R41 closed `cow`
    # and `owner_domain` on exactly this argument: a Populate mints a NEW object
    # and the previous occupant has no claim on it. owner_hart was left.
    #
    # IT IS OBSERVABLE ON ONE HART ONLY BECAUSE MILESTONE 12 BUILT A FIXTURE FOR
    # IT: some slots are seeded owner_hart = 0x63, "hart 99" -- a value that is
    # neither VEDA_OWNER_UNOWNED (0xFF) nor MHARTID (0x00), so owner_ok refuses
    # them. That refusal is the probe, and NOTHING SOFTWARE CAN DO ON ONE HART
    # PRODUCES IT, which is why this property cannot be tested fixture-free.
    #
    # THE TWO LAYERS SEED DIFFERENT SLOTS, so this property needs one test per
    # layer rather than one shared file: Sail seeds objects 5 and 615, the RTL
    # seeds entries 60, 105 and 109. Using the RTL's ids here reported a trap
    # with the WRONG CAUSE and would have passed for the wrong reason had the
    # cause not been asserted as a value.
    # ═══════════════════════════════════════════════════════════════════════
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0
    li   s1, 0

    # ═══ CONTROL 1 -- the fixture is what this test thinks it is ══════════
    # A plain Bind of object 60 must hard-trap with OWNER (cause 0x06). If it
    # does not, the seed has changed and every assertion below is vacuous.
    li   a1, 5
    .insn i 0x0b, 0x5, x3, a1, 0            # veda.bind c3, 5 -- PLAIN
    li   t4, 1
    bne  s0, t4, check_fail
    andi t4, s1, 0x1f
    li   t3, 0x06
    bne  t4, t3, check_fail                 # OWNER violation, as seeded
    .insn r 0x5b, 0x0, 0x03, t3, x3, x0
    bne  t3, x0, check_fail                 # and it minted nothing

    # ═══ THE FINDING -- re-mint the slot, and the owner must go with it ═══
    la   t0, arena
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 5
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # veda.odt.populate 5 -- a NEW object
    li   t4, 1
    bne  s0, t4, check_fail                 # the populate itself must not trap

    li   a1, 5
    .insn i 0x0b, 0x5, x4, a1, 0            # veda.bind c4, 5 -- PLAIN
    li   t4, 1
    bne  s0, t4, check_fail                 # MUST NOT have trapped again
    .insn r 0x5b, 0x0, 0x03, t3, x4, x0
    li   t4, 1
    bne  t3, t4, check_fail                 # and it MUST have minted

    # ═══ CONTROL 2 -- the capability is usable, not merely tagged ═════════
    li   t1, 0
    li   t2, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, t2, x4, t1     # ocs.d c4
    li   t3, 0
    .insn r 0x0b, 0x3, 0x00, t3, x4, t1     # ocl.d  c4
    li   t4, 0xC0FFEE
    bne  t3, t4, check_fail

    # ═══ CONTROL 3 -- owner_ok STILL REFUSES an untouched 0x63 slot ══════
    # Checked here, before 615 is re-minted, because it is the word that stops a
    # machine which simply stopped checking owner_ok from passing this file.
    li   a1, 615
    .insn i 0x0b, 0x5, x5, a1, 0            # veda.bind c5, 615 -- must trap OWNER
    li   t4, 2
    bne  s0, t4, check_fail
    andi t4, s1, 0x1f
    li   t3, 0x06
    bne  t4, t3, check_fail

    # ═══ THE SAME FOR DESTROY ════════════════════════════════════════════
    li   a1, 615
    .insn r 0x0b, 0x1, 0x03, x5, a1, x0     # veda.odt.destroy 615
    la   t0, arena
    slli t0, t0, 32
    li   t1, (32 << 16) | 0x000C
    or   a2, t0, t1
    li   a1, 615
    .insn r 0x0b, 0x0, 0x03, x5, a1, a2     # and re-mint it
    li   a1, 615
    .insn i 0x0b, 0x5, x6, a1, 0            # veda.bind c6, 615 -- PLAIN
    li   t4, 2
    bne  s0, t4, check_fail                 # no third trap
    .insn r 0x5b, 0x0, 0x03, t3, x6, x0
    li   t4, 1
    bne  t3, t4, check_fail                 # bound

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi s0, s0, 1
    csrr s1, mtval
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret

.section .data
.balign 32
arena:
    .space 32
