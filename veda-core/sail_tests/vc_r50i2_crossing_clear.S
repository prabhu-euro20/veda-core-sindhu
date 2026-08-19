.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R50 increment 2 -- the crossing clears capability registers by default.
#
# R50 measured the possession channel and left it open: OCInvoke's only
# capability write is the IDC, OCReturn writes none, and the dereference checker
# has ZERO domain terms -- so a callee needs no authority at all, it uses a
# register the caller left bound. R48 closed the mint channel; this closes the
# possession one.
#
# THE ABI: CSR 0x8CA veda_xretain. Bit i set means capability register i SURVIVES
# the next crossing. Never written means zero means retain NOTHING, so silence
# means clear and never leak. SELF-CONSUMING, so a mask cannot survive to apply
# to a later crossing.
#
# THIS FILE CARRIES THE DISCRIMINATION. The other 37 crossings in the corpus
# declare RETAIN ALL because they measure other mechanisms; if the clear were
# deleted they would all still pass. Round 1 below fails if the clear is absent,
# and round 2 fails if the mask is ignored and everything is always cleared.
#
# Integer registers are untouched -- the clear is capability-file only -- so the
# evidence survives the crossings in x-registers.
#
# Every register by number. x27 traps, x26 mtval, x17 handler temp, x16 round.
.equ SECRET, 760
.equ C_CODE, 761
.equ C_DATA, 762
.equ AUTH,   763
.equ SENTRY, 764
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x16, 0

    li   x1, AUTH
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, compartment
    slli x6, x6, 32
    li   x7, 0x02000402
    or   x2, x6, x7
    li   x1, C_CODE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, C_DATA
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, SENTRY
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8
    la   x6, secret
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, SECRET
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    # Ambient creation now stamps VEDA_DOMAIN_BOOT instead of VEDA_DOMAIN_ANY,
    # so an object is no longer public by accident. This file needs FIVE
    # declarations rather than one, and the reason is structural: `setup:` below
    # is RE-ENTERED from `rebuild` after the first OCReturn, so on the second
    # pass every one of these binds runs from INSIDE a compartment. The
    # compartment's identity is the sentry's object, region 0, so region 0 is
    # what boot declares.
    #
    # x1/x2/x5 are reused deliberately: this file uses all 32 registers, and
    # these three are the populate block's own scratch, dead from here until
    # `setup:` reloads them.
    li   x2, 0
    li   x1, AUTH
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, C_CODE
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, C_DATA
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, SENTRY
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, SECRET
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    bne  x27, x0, fail
setup:
    li   x1, AUTH
    .insn i 0x0b, 0x5, x7, x1, 0
    li   x1, C_CODE
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, C_DATA
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7     # sealed pair -> c3/c4
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7
    li   x1, SENTRY
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0   # csealentry c13 -- the way back
    li   x1, SECRET
    .insn i 0x0b, 0x5, x10, x1, 0
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x10, x8    # ocs.d c10 -- the caller's secret
    li   x19, 1
    beq  x16, x19, round2
    # ROUND 1: retain ONLY the sentry. c10 must NOT survive.
    # R75/R76: boot DECLARES who may bind this. Ambient creation stamps
    # VEDA_DOMAIN_BOOT now, so sharing is a declaration, not a default.
    li   x11, 763
    li   x14, 0
    .insn r 0x0b, 0x1, 0x06, x29, x11, x14
    li   x31, 0x2000                        # bit 13
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4
    j    fail
round2:
    # ROUND 2: retain the sentry AND c10. The read must now SUCCEED.
    li   x31, 0x2400                        # bits 13 and 10
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4
    j    fail
.balign 4
compartment:
    li   x8, 0
    li   x18, 0
    .insn r 0x0b, 0x3, 0x00, x18, x10, x8   # ocl.d through the CALLER's c10
    li   x19, 1
    beq  x16, x19, r2check
    mv   x20, x27
    mv   x21, x26
    mv   x22, x18
    li   x16, 1
    li   x31, 0                             # nothing survives the return
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0
    j    fail
r2check:
    mv   x23, x27
    mv   x24, x18
    li   x16, 2
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0
    j    fail
.balign 4
landing:
    li   x19, 1
    beq  x16, x19, rebuild
    j    check
.balign 4
rebuild:
    # the callee's IDC must NOT have come back: OCRETURN installs none, and c15
    # is deliberately not exempt on the return leg.
    .insn r 0x5b, 0x0, 0x03, x25, x15, x0   # cgettag c15 -- must be 0
    j    setup
.balign 4
check:
    li   x19, 1
    bne  x20, x19, fail                     # ROUND 1: exactly one trap
    andi x19, x21, 0x1f
    li   x28, 0x02
    bne  x19, x28, fail                     # and a TAG violation -- c10 CLEARED
    bnez x22, fail                          # and nothing was read
    bnez x25, fail                          # the callee's IDC did not come back
    li   x19, 1
    bne  x23, x19, fail                     # ROUND 2: no NEW trap
    li   x28, 0xC0FFEE
    bne  x24, x28, fail                     # and the RETAINED capability works,
                                            # so the mask is read and the clear
                                            # is not simply unconditional
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
.section .data
.balign 64
secret:
    .space 64
