.include "veda_selfcheck_macros.S"
# NOT RUN BY THE SUITE, DELIBERATELY. The runner globs vc_*.S; this is poc_*.
# A PASS here would mean THE ESCALATION WORKS.
.section .text
.global _start
# R76 -- THE POLICY FIELD THE WHOLE DOMAIN MODEL RESTS ON HAS NO OWNERSHIP GATE.
#
# veda.odt.set.domain's COMPLETE authorisation, veda_ocl_insts.sail:1252, is
#     if not(cur_privilege == Machine | veda_oda_authorized()) then Illegal_Instruction()
# and NOWHERE in the sixty-line clause is the actor's own domain compared to the
# entry's owner_domain. So the field that says WHO MAY BIND AN OBJECT can be
# re-stamped by an actor that does not own it. R75 forges the identity to satisfy
# the gate; this does not bother -- it rewrites the gate's own input.
#
# SEVERITY, STATED RATHER THAN INFLATED. Reaching it needs cur_privilege ==
# Machine or a delegated ODA, and R47/R48/R69 scoped the ODA and clear it at both
# crossings. So this is a MACHINE-MODE escalation. This file measures BOTH arms,
# because "it needs Machine" is only a mitigation if User is genuinely refused.
#
# Every register by NUMBER.
.equ SECRET,   300
.equ TYPEAUTH, 302
.equ SENTRY,   303
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
    li   x24, 0
    li   x28, 0

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

    # the owner narrows its own object to domain 0
    li   x1, SECRET
    li   x4, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
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
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # -> compB, region 1, still Machine
    j    fail

.balign 4
compB:
    # ═══ CONTROL -- B is genuinely refused the object it does not own ═══
    li   x1, SECRET
    .insn i 0x0b, 0x5, x5, x1, 1
    .insn r 0x5b, 0x0, 0x03, x21, x5, x0   # MUST be 0

    # ═══ ARM 1, AT MACHINE -- do not forge the identity, REWRITE THE POLICY ═══
    li   x1, SECRET
    li   x4, 1                             # "this object is mine now"
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4    # veda.odt.set.domain SECRET <- 1
    mv   x20, x27                          # MUST still be 0 -- it was allowed
    li   x1, SECRET
    .insn i 0x0b, 0x5, x6, x1, 1
    .insn r 0x5b, 0x0, 0x03, x22, x6, x0   # 1 = the re-stamp worked
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x23, x6, x8   # 0xC0FFEE = the secret

    # ═══ ARM 2, AT USER -- the same instruction must be REFUSED ═══
    la   x30, u_probe
    csrw mepc, x30
    li   x30, 0x1800
    csrc mstatus, x30
    mret

.balign 4
u_probe:
    mv   x25, x27                          # traps before
    li   x1, SECRET
    li   x4, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4    # MUST trap: unprivileged, no ODA
    mv   x24, x27                          # MUST have grown by exactly one
    ecall

.balign 4
landing:
    ecall

.balign 4
trap_handler:
    csrr x17, mcause
    li   x18, 8
    beq  x17, x18, verdict
    li   x18, 11
    beq  x17, x18, verdict
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret

.balign 4
verdict:
    bnez x28, fail
    bnez x21, fail                         # CONTROL: refused before the re-stamp
    bnez x20, fail                         # ARM 1: set.domain was ALLOWED at Machine
    li   x18, 1
    bne  x22, x18, fail                    # and the bind then SUCCEEDED
    li   x18, 0xC0FFEE
    bne  x23, x18, fail                    # and the secret was read
    li   x18, 1
    sub  x19, x24, x25
    bne  x19, x18, fail                    # ARM 2: at User it trapped, exactly once
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
