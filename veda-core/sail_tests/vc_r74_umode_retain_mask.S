.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R74 -- THE RETAIN MASK WAS UNREACHABLE BY THE ONLY SOFTWARE THAT NEEDS IT.
#
# R71 built the crossing's capability-file clear and put its retain mask in CSR
# 0x7CA. Privilege on this machine is derived from the CSR ADDRESS -- csrPriv(csr)
# = csr[9..8], and 0x7CA gives 0b11 -- so the mask was MACHINE-ONLY. R71's own
# text says "a compartment that wants to pass capabilities onward must set the
# CSR ITSELF, inside its own PCC window", and compartments are unprivileged by
# definition. The instruction it told them to execute would trap.
#
# MEASURED before the fix: veda_smoke_r48_oda_crossing.S writes the mask AFTER
# its architected drop to User. Its trap counter read 2, not 1 -- the mask write
# trapped, the mask stayed zero, the crossing cleared everything, and the RTL
# suite passed 110/110 without anyone noticing. The thirteenth green that
# measured nothing.
#
# WORSE THAN A DEAD WRITE, and this is why it is a finding rather than a typo:
# with the register channel shut to unprivileged code and the memory channel
# (R72) ungoverned, R71 pushed ALL User-mode delegation onto the one path that
# asks no questions.
#
# THE FIX: address 0x8CA. Verified against the official RISC-V Privileged
# specification's CSR address-allocation table (chapter "Control and Status
# Registers", table "Allocation of RISC-V CSR address ranges"): 0x800-0x8FF is
# the ONLY Custom, read/write, User-level range in the entire table, bits [7:4]
# are unconstrained so all 256 addresses are available, and the specification
# guarantees custom addresses "will not be redefined by future standard
# extensions". csrPriv(0x8CA) = 0b00 (User) and csrAccess(0x8CA) = 0b10 (not
# read-only), so NO privilege-check logic changes on either layer -- only the
# address constant. 0xCC0-0xCFF was rejected: it is Custom READ-ONLY, and a
# write to it must raise an illegal instruction.
#
# THIS FILE ASSERTS BOTH HALVES, and the second is the load-bearing one.
#   (1) An unprivileged compartment CAN now arm the mask and delegate.
#   (2) RETAIN NEVER BECOMES GRANT. A set bit means "do not clear", never
#       "materialize". c9 is retained while holding nothing, and it must come
#       out of the crossing still holding nothing AND still unusable. If any
#       future path ever reads a set bit as a grant, User-writability turns into
#       escalation on the spot -- so the invariant gets a test, not a comment.
#
# Register choice is not incidental: c10..c14 are FIXTURE-SEEDED, so an
# "is it empty" assertion on one of them would read the seed. c9 is not seeded.
# Every register by NUMBER.
.equ SECRET,  400
.equ C_CODE,  16777256
.equ C_DATA,  16777257
.equ TYPEAUTH, 402
.equ SENTRY,  403
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

    li   x1, SECRET
    li   x2, 0x800110000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, TYPEAUTH
    li   x2, 0x8001130000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, compartment
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, C_CODE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, C_DATA
    li   x2, 0x8001120000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, SENTRY
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8

    li   x1, C_CODE
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, C_DATA
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, TYPEAUTH
    .insn i 0x0b, 0x5, x7, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7
    li   x1, SENTRY
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0
    li   x1, SECRET
    .insn i 0x0b, 0x5, x10, x1, 0          # c10 -- the caller's own capability
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x10, x8   # plant the value
    bne  x27, x0, fail                     # setup must be clean

    # --- Drop M-mode -> U-mode via mret. mstatus.MPP is bits [12:11];
    #     clearing both (mask 0x1800) sets MPP = 0b00 = User. The capability
    #     register file is untouched by trap entry and by xret, so everything
    #     bound above is still bound on the other side.
    la   x30, u_entry
    csrw mepc, x30
    li   x30, 0x1800
    csrc mstatus, x30
    mret

.balign 4
u_entry:
    # ═══ GENUINELY UNPRIVILEGED FROM HERE ═══════════════════════════════════
    # (1) THE WRITE THAT USED TO TRAP. Retain the sentry (c13), the caller's own
    #     capability (c10), and -- deliberately -- the EMPTY c9.
    li   x31, 0x2600                       # bits 13, 10 and 9
    csrw 0x8CA, x31
    mv   x20, x27                          # MUST still be 0: no trap at User
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # ocinvoke
    j    fail

.balign 4
compartment:
    li   x8, 0
    # (1) the delegated capability arrived and works
    .insn r 0x0b, 0x3, 0x00, x21, x10, x8  # ocl.d through the RETAINED c10
    # (2) RETAIN IS NOT GRANT -- c9 was retained while empty
    .insn r 0x5b, 0x0, 0x03, x22, x9, x0   # cgettag c9 -- MUST be 0
    mv   x23, x27                          # traps before the deliberate one
    .insn r 0x0b, 0x3, 0x00, x25, x9, x8   # ocl.d through it -- MUST TRAP 0x02
    mv   x24, x27                          # MUST have grown by exactly one
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0   # ocreturn
    j    fail

.balign 4
landing:
    ecall                                  # back to Machine for the verdict

.balign 4
trap_handler:
    csrr x17, mcause
    li   x18, 8
    beq  x17, x18, verdict                 # ecall from User
    li   x18, 11
    beq  x17, x18, verdict                 # ecall from Machine
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret

.balign 4
verdict:
    bnez x20, fail                         # (1) the User CSR write did NOT trap
    li   x18, 0xC0FFEE
    bne  x21, x18, fail                    # (1) and the delegation genuinely worked
    bnez x22, fail                         # (2) a retained EMPTY register is still empty
    bnez x23, fail                         # no stray trap before the deliberate one
    li   x18, 1
    bne  x24, x18, fail                    # (2) and using it trapped, exactly once
    andi x18, x26, 0x1f
    li   x19, 0x02
    bne  x18, x19, fail                    # with cause TAG_VIOLATION -- retain != grant
    bnez x25, fail                         # and nothing was read through it
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
