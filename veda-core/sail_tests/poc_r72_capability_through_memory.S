.include "veda_selfcheck_macros.S"
# NOT RUN BY THE SUITE, DELIBERATELY. The runner globs vc_*.S; this is poc_*.
#
# A PASS here would mean THE ESCALATION WORKS. A suite whose green means the hole
# is open is exactly the failure R73 recorded one finding earlier -- a test that
# freezes an observation into a contract. This file is the MEASUREMENT, kept in
# the repo rather than in a scratchpad so the evidence outlives the session, and
# it is to be REWRITTEN as a vc_ negative test when the mechanism lands.
#
# Reproduce:
#   as -march=rv64i_zicsr -I. -o /tmp/p.o <this file>
#   ld -T ./veda_selfcheck.ld -o /tmp/p.elf /tmp/p.o
#   sail_riscv_sim --config ./veda_test_sail.json --inst-limit 2000000 \
#       --trace-instr --trace-gpr /tmp/p.elf
#
.section .text
.global _start
# R72 PROBE -- does a capability escape its domain THROUGH MEMORY?
#
# R71 clears the capability register file at every crossing. This probe asks
# whether that closed the channel or merely moved it. The decisive move is
# CONTROL 1: the SECRET object is locked to domain 0 with set.domain, so
# compartment B -- executing from a region-1 code object -- CANNOT bind it by
# name. If B still reads it, the escape is NOT redundant with the R52 bind gate
# and R71 did not close it.
#
# Every register by NUMBER. x27 traps, x26 mtval.
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

    # ---- SECRET: region 0, Perms LOAD|STORE ----
    li   x1, 200
    li   x2, 0x800110000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # ---- SHARED: region 0, Perms LOAD|STORE|LOAD_CAP|STORE_CAP = 0x3C ----
    li   x1, 201
    li   x2, 0x800111000040003C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # ---- type authority, ambient -> owner_domain ANY ----
    li   x1, 202
    li   x2, 0x8001130000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # ---- compartment B: CODE and DATA in REGION 1 ----
    la   x6, compB
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, 16777246                       # {region 1, local 30}
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 16777247                       # {region 1, local 31}
    li   x2, 0x8001120000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # ---- the way back: unbounded sentry over `landing` ----
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, 203
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8

    # ═══ LOCK THE SECRET TO DOMAIN 0. B executes in region 1, so after this
    #     B may not bind object 200 by name at all.
    li   x1, 200
    li   x4, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4     # veda.odt.set.domain 200 -> domain 0
    mv   x25, x27                            # no trap allowed so far

    # ---- domain 0 plants the secret, then publishes the CAPABILITY ----
    li   x1, 200
    .insn i 0x0b, 0x5, x1, x1, 0            # veda.bind c1, 200
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x1, x8     # ocs.d c1 -- plant the secret
    li   x1, 201
    .insn i 0x0b, 0x5, x2, x1, 0            # veda.bind c2, 201  (SHARED)
    .insn r 0x0b, 0x4, 0x01, x1, x2, x8     # ocs.c  mem=c2, src=c1, off=0
                                            #   <-- the SECRET capability is now
                                            #       lying in shared memory

    # ---- build the sealed pair and the sentry ----
    li   x1, 16777246
    .insn i 0x0b, 0x5, x3, x1, 0
    li   x1, 16777247
    .insn i 0x0b, 0x5, x4, x1, 0
    li   x1, 202
    .insn i 0x0b, 0x5, x7, x1, 0
    .insn r 0x5b, 0x1, 0x10, x8, x3, x7     # cseal c8, c3, c7
    .insn r 0x5b, 0x1, 0x10, x9, x4, x7     # cseal c9, c4, c7
    li   x1, 203
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0   # csealentry c13

    mv   x20, x27                            # trap count entering the crossing
    # RETAIN ONLY THE SENTRY. R71 clears c1 and c2 -- the caller hands the
    # callee no capability register at all.
    li   x31, 0x2000
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9     # ocinvoke c8, c9
    j    landing

.balign 4
compB:
    # ═══ Region 1. R71 has cleared c0..c14; only c13 and the fresh IDC c15 live.
    #
    # CONTROL 1 -- THE NAME IS NOT AUTHORITY HERE. Object 200 is owned by
    # domain 0. A bind by name must fail. If this control does not hold, the
    # attack below proves nothing, because B could have had the object anyway.
    li   x1, 200
    .insn i 0x0b, 0x5, x5, x1, 1            # veda.bind.notrap c5, 200
    .insn r 0x5b, 0x0, 0x03, x21, x5, x0    # cgettag c5 -> x21  MUST BE 0
    mv   x24, x27                            # trap count after the control

    # ═══ THE ATTACK -- take the capability out of shared memory instead.
    li   x1, 201
    .insn i 0x0b, 0x5, x6, x1, 0            # veda.bind c6, 201  (SHARED is ANY)
    li   x8, 0
    .insn r 0x0b, 0x4, 0x00, x7, x6, x8     # ocl.c c7 <- [c6 + 0]
    .insn r 0x5b, 0x0, 0x03, x22, x7, x0    # cgettag c7 -> x22
    .insn r 0x0b, 0x3, 0x00, x23, x7, x8    # ocl.d x23 <- [c7 + 0]
                                            #   0xC0FFEE here = ESCAPE CONFIRMED
    li   x31, 0
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0    # ocreturn c13

.balign 4
landing:
    # verdict, by branches -- nothing packed into a halt payload
    li   x28, 0xC0FFEE
    bne  x23, x28, no_escape                # B did not read the secret
    bnez x21, control_failed                # B could bind by name anyway
    RVMODEL_HALT_PASS                       # ESCAPE CONFIRMED, and not via the name
no_escape:
    RVMODEL_HALT_FAIL
control_failed:
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
