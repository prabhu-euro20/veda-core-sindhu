.include "veda_selfcheck_macros.S"
# NOT RUN BY THE SUITE, DELIBERATELY. The runner globs vc_*.S; this is poc_*.
# A PASS here means the escalation works.
.section .text
.global _start
# R72 FORM 2 -- THE COPY-ON-WRITE SPLIT ENTITLEMENT IS A BEARER TOKEN.
#
# R38 chose PERM_STORE-carried-in-a-capability as the token for "may force the
# copy", and wrote the rule down at veda_ocl_insts.sail:127:
#     "WHOEVER HELD WRITE AUTHORITY AT THE MOMENT THE OBJECT BECAME
#      COPY-ON-WRITE MAY CAUSE THE SPLIT ... the copy is owed to the writers
#      that existed at fork, not to anyone who later learns the NAME."
# It defended that against RE-BIND (veda_bind_perms masks a cow entry's Perms
# with 0xFFF7, so a fresh bind cannot carry STORE) and against CAndPerm.
# IT NEVER CONSIDERED TRANSFER.
#
# Three facts, each verified at source:
#   1. veda_ocl_insts.sail:256  else if need_store & entry.cow then COW_FAULT
#      0x0C is NOT a refusal. R38's own text calls it a REPAIR REQUEST: it
#      instructs a handler to allocate, copy, and hand back a fresh writable
#      object. Forcing it is an ALLOCATION on someone else's behalf.
#   2. veda_ocl_insts.sail:1321  set.cow does NOT bump the generation --
#      "that is the entire purpose of this" -- so a capability minted BEFORE
#      the object became copy-on-write stays live and keeps PERM_STORE.
#   3. VEDA_OCS_C / VEDA_OCL_C move that capability through memory, and
#      veda_check_access has ELEVEN arms and ZERO domain terms.
#
# AND IT NEEDS NO DOMAIN NARROWING AT ALL, which is what separates it from
# R72 Form 1: it bites in the DEFAULT configuration.
#
# THE DISCRIMINATOR IS THE CAUSE CODE. A capability B could mint for itself
# carries no STORE, so a store through it gives 0x13 PERM_STORE. The
# TRANSFERRED one carries STORE, so it reaches the cow arm and gives 0x0C --
# the repair request. 0x0C where 0x13 belongs is the whole finding.
#
# Every register by NUMBER.
.equ VICTIM,   400
.equ SHARED,   401
.equ TYPEAUTH, 402
.equ SENTRY,   403
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

    li   x1, VICTIM
    li   x2, 0x800110000040000C            # LOAD|STORE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, SHARED
    li   x2, 0x800111000040003C            # LOAD|STORE|LOAD_CAP|STORE_CAP
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

    # boot delegates only what B legitimately needs: its own code and data, and
    # the SHARED container. VICTIM is never delegated -- B has no route to it.
    li   x4, 1
    li   x1, CODE_B
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, DATA_B
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, SHARED
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4

    # ═══ A BINDS THE VICTIM *BEFORE* IT BECOMES COPY-ON-WRITE ════════════════
    li   x1, VICTIM
    .insn i 0x0b, 0x5, x1, x1, 0           # c1 carries PERM_STORE
    li   x1, VICTIM
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4    # veda.odt.set.cow VICTIM <- 1
                                           # generation NOT bumped: c1 stays live
    # ═══ AND PUBLISHES THE TOKEN INTO SHARED MEMORY ══════════════════════════
    li   x1, SHARED
    .insn i 0x0b, 0x5, x2, x1, 0
    li   x8, 0
    .insn r 0x0b, 0x4, 0x01, x1, x2, x8    # ocs.c mem=c2, src=c1
    mv   x28, x27                          # setup must be clean

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
    # ═══ CONTROL -- B HAS NO ROUTE TO THE VICTIM BY NAME ═════════════════════
    li   x1, VICTIM
    .insn i 0x0b, 0x5, x5, x1, 1
    .insn r 0x5b, 0x0, 0x03, x21, x5, x0   # MUST be 0
    mv   x24, x27                          # and quietly

    # ═══ THE TRANSFER -- take the token out of shared memory ═════════════════
    li   x1, SHARED
    .insn i 0x0b, 0x5, x6, x1, 0
    li   x8, 0
    .insn r 0x0b, 0x4, 0x00, x7, x6, x8    # ocl.c c7 <- [c6 + 0]
    .insn r 0x5b, 0x0, 0x03, x22, x7, x0   # tagged? MUST be 1
    li   x9, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x9, x7, x8    # ocs.d through it -- what cause?
    mv   x20, x27
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0

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
    bnez x28, fail                         # setup was clean
    bnez x21, fail                         # CONTROL: no route by name
    bnez x24, fail                         # and quietly
    li   x18, 1
    bne  x22, x18, fail                    # the transferred token is TAGGED
    andi x18, x26, 0x1f
    li   x19, 0x0c
    bne  x18, x19, fail                    # AND THE CAUSE IS 0x0C, THE REPAIR
                                           # REQUEST -- not 0x13, the refusal
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
