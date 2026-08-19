.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R73 -- A DOMAIN REFUSAL IS MODE-DEPENDENT, LIKE EVERY OTHER REFUSAL HERE.
#
# The per-object bind gate used to trap for ALL THREE bind modes. Nothing said
# why. It was written beside the residency gate and inherited residency's
# all-modes policy without inheriting residency's ARGUMENT -- and that argument
# does not transfer: residency and region traps for every mode so the holder
# goes and SERVICES something ("paged out, retry"), while a domain refusal has
# nothing to service. Milestone 12 set the rule for ownership refusals and the
# owner_hart arm still implements it: plain Bind hard-traps, Bind-NoTrap
# soft-fails, "matching its own established convention for every other failure
# reason". This gate was the one exception, and it was silent.
#
# R43 is why it mattered beyond tidiness: R43 justified a soft-fail by citing
# the comment above the Rebind arm -- "Rebind never traps for ANY failure
# reason, owner mismatch included" -- and that sentence was FALSE AT SOURCE.
#
# THREE MODES, THREE DIFFERENT CORRECT ANSWERS, and this file asserts all of
# them. The plain-Bind row is the ANTI-VACUITY CONTROL: without it, a machine
# that simply DELETED the domain gate would satisfy both soft-fail rows.
#
# The two soft-fails have DIFFERENT SHAPES and the file discriminates them:
#   Bind-NoTrap zeroes the register and clears Tag.
#   Rebind clears Tag ONLY, preserving every field including Base and Offset
#   (VEDA_CORE_SPEC.md Section 4, and RTL-4's own note). A test that only
#   checked the tag could not tell the two apart.
#
# Every register by NUMBER: t4 IS x29, s11 IS x27 and t3 IS x28, and this
# project has three times turned a check into a register compared with itself.
.equ FOREIGN, 300
.equ OPEN,    301
.equ CODE_B,  16777246
.equ DATA_B,  16777247
.equ TYPEAUTH, 302
.equ SENTRY,  303
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x25, 0
    li   x28, 0

    li   x1, FOREIGN
    li   x2, 0x800110000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, OPEN
    li   x2, 0x800111000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, TYPEAUTH
    li   x2, 0x8001130000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, compB
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, CODE_B                          # {region 1, local 30}
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, DATA_B                          # {region 1, local 31}
    li   x2, 0x8001120000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, SENTRY
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8

    # Lock FOREIGN to domain 0. compB executes from a REGION 1 code object, so
    # veda_bind_domain_ok fails for it and passes for everyone ambient.
    li   x1, FOREIGN
    li   x4, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    mv   x28, x27                            # no trap allowed in setup

    li   x1, CODE_B
    .insn i 0x0b, 0x5, x3, x1, 0
    li   x1, DATA_B
    .insn i 0x0b, 0x5, x4, x1, 0
    li   x1, TYPEAUTH
    .insn i 0x0b, 0x5, x7, x1, 0
    .insn r 0x5b, 0x1, 0x10, x8, x3, x7
    .insn r 0x5b, 0x1, 0x10, x9, x4, x7
    li   x1, SENTRY
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0
    # R75/R76: boot DECLARES who may bind this. Ambient creation stamps
    # VEDA_DOMAIN_BOOT now, so sharing is a declaration, not a default.
    li   x10, 301
    li   x11, 1
    .insn r 0x0b, 0x1, 0x06, x14, x10, x11
    li   x31, 0x2000                         # retain only the sentry (R71)
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9
    j    fail

.balign 4
compB:
    # ═══ ROW 1 -- REBIND. Tag cleared, EVERY OTHER FIELD PRESERVED. ═══
    li   x1, OPEN
    .insn i 0x0b, 0x5, x1, x1, 0             # veda.bind c1, OPEN -- a real one
    .insn r 0x5b, 0x0, 0x00, x20, x1, x0     # cgetbase c1 -> x20, the reference
    li   x1, FOREIGN
    .insn i 0x0b, 0x5, x1, x1, 2             # veda.rebind c1 against FOREIGN
    .insn r 0x5b, 0x0, 0x03, x21, x1, x0     # tag MUST be 0
    .insn r 0x5b, 0x0, 0x00, x22, x1, x0     # Base MUST still equal x20

    # ═══ ROW 2 -- BIND-NOTRAP. Register ZEROED and Tag cleared. ═══
    li   x1, OPEN
    .insn i 0x0b, 0x5, x2, x1, 0             # a real capability first, so a
    li   x1, FOREIGN                         # cleared tag below proves a WRITE
    .insn i 0x0b, 0x5, x2, x1, 1             # veda.bind.notrap c2
    .insn r 0x5b, 0x0, 0x03, x23, x2, x0     # tag MUST be 0
    .insn r 0x5b, 0x0, 0x00, x24, x2, x0     # Base MUST be 0 -- a DIFFERENT
                                             # soft-fail shape from Rebind's
    mv   x25, x27                            # MUST still be 0 -- neither trapped

    # ═══ ROW 3 -- PLAIN BIND. The anti-vacuity control: the gate must still
    # be there, and it must still be LOUD, with the right cause. ═══
    li   x1, FOREIGN
    .insn i 0x0b, 0x5, x3, x1, 0             # veda.bind c3 -- MUST trap 0x0B
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0     # ocreturn
    j    fail

.balign 4
landing:
    bnez x28, fail                           # setup was clean
    bnez x21, fail                           # ROW 1: Rebind cleared the tag
    bne  x22, x20, fail                      # ROW 1: and PRESERVED Base
    beqz x20, fail                           # (and the reference was not 0,
                                             #  so the comparison means something)
    bnez x23, fail                           # ROW 2: NoTrap cleared the tag
    bnez x24, fail                           # ROW 2: and ZEROED the register
    bnez x25, fail                           # neither soft-fail trapped
    li   x29, 1
    bne  x27, x29, fail                      # ROW 3: exactly one trap, the loud one
    andi x29, x26, 0x1f
    li   x30, 0x0b
    bne  x29, x30, fail                      # and its cause was DOMAIN_VIOLATION
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
