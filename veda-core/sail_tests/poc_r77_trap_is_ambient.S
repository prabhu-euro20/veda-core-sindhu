.include "veda_selfcheck_macros.S"
# NOT RUN BY THE SUITE, DELIBERATELY. The runner globs vc_*.S; this is poc_*.
# A PASS here means the capability crossed the trap boundary.
.section .text
.global _start
# R77 -- THE TRAP PATH IS A FOURTH COMPARTMENT ENTRY WITH ROOT AUTHORITY AND NO
#        REGISTER BARRIER, AND R75/R76 INCREMENT 1 MADE THAT AUTHORITY LARGER.
#
# Two facts, each read at source, that compose into one:
#
#   1. veda_pcc_save_and_reset (veda_regs.sail:321-361) sets
#          veda_pcc_object = VEDA_OBJECT_NONE
#      on every trap. VEDA_OBJECT_NONE is exactly the AMBIENT sentinel, and
#      since R75/R76 increment 1 ambient is THE ROOT OF ALL AUTHORITY: arm 2 of
#      veda_bind_domain_ok passes it everything, and set.domain's new ownership
#      term exempts it so that boot can perform the initial delegation.
#
#   2. veda_crossing_clear has EXACTLY TWO call sites -- veda_cap_insts.sail:604
#      (OCInvoke) and :930 (OCReturn). Verified by grep. Neither trap entry nor
#      xret is among them, so the capability register file crosses a trap
#      INTACT IN BOTH DIRECTIONS.
#
# So a compartment reaches a root-authority context by FAULTING, and anything
# that context mints comes back with it. Before increment 1 this was unremarkable
# because every object was VEDA_DOMAIN_ANY and ambient was not special. Closing
# the creation default is what turned ambient into the root -- so this is a
# consequence of my own increment, measured rather than reasoned about.
#
# This file does NOT claim an unassisted escape: the handler is trusted code and
# a compartment cannot install its own. What it measures is the SIZE of that
# trust, which grew.
#
# Every register by NUMBER.
.equ SECRET,   200
.equ TYPEAUTH, 202
.equ SENTRY,   203
.equ CODE_B,   16777246
.equ DATA_B,   16777247
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x28, 0
    li   x29, 0

    li   x1, SECRET
    li   x2, 0x800110000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, TYPEAUTH
    li   x2, 0x8001130000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, compB
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, CODE_B
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, DATA_B
    li   x2, 0x8001120000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, SENTRY
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8

    # boot delegates what compB legitimately needs, and NOTHING else
    li   x1, CODE_B
    li   x4, 1
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, DATA_B
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    # SECRET stays boot's: never delegated, so compB may not bind it
    li   x1, SECRET
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x1, x8
    mv   x28, x27

    li   x1, CODE_B
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, DATA_B
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, TYPEAUTH
    .insn i 0x0b, 0x5, x7, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7
    li   x1, SENTRY
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0
    li   x31, 0x2000
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4
    j    fail

.balign 4
compB:
    # ═══ CONTROL -- compB genuinely cannot bind SECRET ═══════════════════════
    li   x1, SECRET
    .insn i 0x0b, 0x5, x5, x1, 1
    .insn r 0x5b, 0x0, 0x03, x21, x5, x0   # MUST be 0
    mv   x29, x27                          # and the quiet form costs no trap

    # ═══ FAULT DELIBERATELY. An ordinary load is refused inside a live
    #     compartment (the purecap rule), so this is the cheapest way in.
    li   x16, 1                            # tell the handler to mint
    ld   x17, 0(x0)                        # -> trap -> ambient handler
    # ── back here after mret, with whatever the handler left in the file ──
    .insn r 0x5b, 0x0, 0x03, x22, x6, x0   # cgettag c6: did it survive mret?
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x23, x6, x8   # and does it still work?
    mv   x20, x27
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0
    j    fail

.balign 4
landing:
    ecall

.balign 4
trap_handler:
    # ═══ AMBIENT. veda_pcc_object is VEDA_OBJECT_NONE here, so every domain
    #     question in the machine answers yes. This handler binds SECRET -- an
    #     object boot never delegated to anybody -- purely to measure whether a
    #     capability minted here reaches the faulting compartment.
    csrr x17, mcause
    li   x18, 8
    beq  x17, x18, verdict
    li   x18, 11
    beq  x17, x18, verdict
    addi x27, x27, 1
    csrr x26, mtval
    li   x18, 1
    bne  x16, x18, skip_mint
    li   x16, 0
    li   x1, SECRET
    .insn i 0x0b, 0x5, x6, x1, 0           # ambient binds it. No gate objects.
skip_mint:
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret

.balign 4
verdict:
    bnez x28, fail                         # setup was clean
    bnez x21, fail                         # CONTROL: compB was refused
    bnez x29, fail                         # quietly
    li   x18, 1
    bne  x22, x18, fail                    # the capability SURVIVED the mret
    li   x18, 0xC0FFEE
    bne  x23, x18, fail                    # and it still reads the secret
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
