.include "veda_selfcheck_macros.S"
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
# R75 -- THE RETURN PATH IS AN ENTRY PATH, AND IT HAS NO ADMISSION CONTROL.
#
# Every domain question this machine asks is asked of veda_pcc_object: the bind
# gate (veda_regs.sail:1165-1168), the creating domain a Populate records
# (veda_ocl_insts.sail:715-717), R62's nameable check, R73's mode-dependent
# refusal. This file measures whether that register can be INSTALLED BY A
# PRINCIPAL THAT WAS NEVER GIVEN THE IDENTITY.
#
# OCInvoke demands a SEALED PAIR -- cs1 code and cs2 data with matching otype --
# which is evidence that the owning domain minted and handed over an entry.
# OCReturn demands only a sentry. And CSealEntry's COMPLETE authorisation, read
# at veda_cap_insts.sail:413, is:
#     let ok : bool = CTag(cs1idx) & not(isSealedCap(cs1));
# no operand, no permission, no privilege. So any holder of any tagged unsealed
# capability mints a sentry from it.
#
# OCReturn's guard chain, read at veda_cap_insts.sail:887-905: tag, sealed,
# otype == SENTRY, PERM_EXECUTE, region rt_resident, then veda_code_object_check
# -- whose ENTIRE body (veda_cap_insts.sail:535-545) is valid, generation,
# resident. THERE IS NO DOMAIN TERM AND NO OWNER TERM. Then :924 executes
#     veda_pcc_object = cs1.Object_ID;
#
# So the chain is four instructions and needs nothing but a NAME:
#     veda.bind c9, <A's code object>   -- owner_domain is ANY, the default
#     csealentry c9, c9                 -- authorised by tag alone
#     ocreturn c9                       -- installs A's Object_ID as the identity
#
# CONTROL FIRST, because a machine on which nothing binds would satisfy the
# attack rows for the wrong reason: before the forge, B is genuinely refused the
# narrowed object. After the forge, the SAME bind must succeed.
#
# Every register by NUMBER.
.equ SECRET,   300
.equ CODE_A,   301
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
    # ---- A's CODE object. REGION 0, Perms EXECUTE|INVOKE, owner_domain left at
    #      the default VEDA_DOMAIN_ANY -- exactly as every shipped code fixture
    #      in this corpus is created. It is never handed to B in any form.
    la   x6, forged
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, CODE_A
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # ---- B's own compartment, REGION 1 ----
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

    # lock the secret to domain 0 -- B executes in region 1 and may not bind it
    li   x1, SECRET
    li   x4, 0
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, SECRET
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x1, x8
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
    li   x31, 0x2000                       # retain ONLY the sentry
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # ocinvoke -> B, region 1
    j    fail

.balign 4
compB:
    # ═══ CONTROL -- B is genuinely refused the narrowed object BY NAME ═══
    li   x1, SECRET
    .insn i 0x0b, 0x5, x5, x1, 1           # veda.bind.notrap c5, SECRET
    .insn r 0x5b, 0x0, 0x03, x21, x5, x0   # MUST be 0
    mv   x24, x27                          # and R73 says this must not trap

    # ═══ THE FORGE -- three instructions, and the only input is a NAME ═══
    li   x1, CODE_A
    .insn i 0x0b, 0x5, x9, x1, 1           # veda.bind.notrap c9, CODE_A
    .insn r 0x5b, 0x0, 0x03, x22, x9, x0   # MUST be 0 -- A's code is not public
    mv   x20, x27                          # and the quiet form added no trap
    ecall                                  # -> verdict

.balign 4
forged:
    # ═══ Executing with veda_pcc_object = CODE_A. The identity is domain 0's,
    #     and no domain ever granted it. The SAME bind the control refused:
    li   x1, SECRET
    .insn i 0x0b, 0x5, x6, x1, 1           # veda.bind.notrap c6, SECRET
    .insn r 0x5b, 0x0, 0x03, x22, x6, x0   # 1 = THE IDENTITY WAS FORGED
    li   x8, 0
    .insn r 0x0b, 0x3, 0x00, x23, x6, x8   # 0xC0FFEE = the secret is readable
    mv   x20, x27
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
    # ═══ INVERTED BY R75/R76 INCREMENT 1 ═══════════════════════════════════
    # This file MEASURED AN ESCALATION and passed when the escalation worked.
    # The mechanism landed, so it is now a NEGATIVE test: same instructions,
    # same objects, opposite verdict. The quiet Bind form is used for the forge
    # so the file can keep running and ASSERT the refusal rather than die on it.
    bnez x28, fail                         # setup was clean
    bnez x21, fail                         # CONTROL: B refused the object by name
    bnez x24, fail                         # and that refusal was the quiet form
    bnez x22, fail                         # THE FORGE: no capability was minted
    bne  x20, x24, fail                    # and it cost no trap either
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
