.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R84 DECISION 2 -- A CAPABILITY MAY NOT ADDRESS A DEVICE.
#
# R84 increment 1 routed OCL.D/OCS.D through the checked memory path so a
# capability can finally reach the CLINT, the signature region and HTIF. The
# CAPABILITY family cannot follow it there: `mmio_write` takes no `meta`, so
# OCS.C to a device would SILENTLY LOSE ITS TAG -- stored-looking and dead.
# A silent downgrade is the shape this register has refused five times, so the
# refusal is loud and carries its own cause, 0x0D DEVICE_VIOLATION.
#
# FIVE ROWS. B and D are the anti-vacuity controls and E is the anti-REGRESSION
# control -- without E this file would pass just as happily on a machine that
# had broken increment 1 and cut the data family off from devices again.
#
#   A  OCS.C into the CLINT      -> REFUSED, cause 0x0D
#   B  OCS.C into ordinary RAM   -> SUCCEEDS   (not a blanket ban)
#   C  OCL.C out of the CLINT    -> REFUSED, cause 0x0D
#   D  OCL.C out of ordinary RAM -> SUCCEEDS, and the capability round-trips
#   E  OCL.D out of the CLINT    -> SUCCEEDS   (increment 1 still stands)
#
# The CLINT is at 0x2000000 size 0xC0000 in this project's own Sail config, so a
# 32-byte access there genuinely matches within_clint. HTIF would NOT do: its own
# term in within_mmio_writable is gated `& 'n <= 8`, so a 32-byte access is not
# classified as MMIO at all.
#
# Every register by NUMBER.
.equ DEVOBJ, 246
.equ RAMOBJ, 247
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0

    li   x6, 0x2000000                      # the CLINT
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x003C            # LOAD|STORE|LOAD_CAP|STORE_CAP
    or   x2, x6, x7
    li   x1, DEVOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, DEVOBJ
    .insn i 0x0b, 0x5, x9, x1, 0

    la   x6, ram
    slli x6, x6, 32
    li   x7, (64 << 16) | 0x003C
    or   x2, x6, x7
    li   x1, RAMOBJ
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, RAMOBJ
    .insn i 0x0b, 0x5, x10, x1, 0
    bnez x27, fail                          # setup was clean

    # ═══ ROW A -- OCS.C into a DEVICE must be refused with 0x0D ═══════════
    li   x8, 0
    .insn r 0x0b, 0x4, 0x01, x10, x9, x8    # ocs.c c9, x8, c10  -- store c10 INTO the device
    li   x17, 1
    bne  x27, x17, fail                     # exactly one trap
    li   x17, 0x0D
    andi x18, x26, 0x1f
    bne  x18, x17, fail                     # and it is DEVICE_VIOLATION

    # ═══ ROW B -- ANTI-VACUITY: the same store into RAM must SUCCEED ══════
    .insn r 0x0b, 0x4, 0x01, x10, x10, x8   # ocs.c c10, x8, c10
    li   x17, 1
    bne  x27, x17, fail                     # still exactly one trap -- none added

    # ═══ ROW C -- OCL.C out of a DEVICE must be refused with 0x0D ═════════
    .insn r 0x0b, 0x4, 0x00, x11, x9, x8    # ocl.c c11, c9, x8
    li   x17, 2
    bne  x27, x17, fail
    li   x17, 0x0D
    andi x18, x26, 0x1f
    bne  x18, x17, fail

    # ═══ ROW D -- ANTI-VACUITY: the same load out of RAM must SUCCEED, and
    #             the capability must come back TAGGED ════════════════════
    .insn r 0x0b, 0x4, 0x00, x12, x10, x8   # ocl.c c12, c10, x8
    li   x17, 2
    bne  x27, x17, fail                     # no new trap
    .insn r 0x5b, 0x0, 0x03, x19, x12, x0   # cgettag c12
    li   x17, 1
    bne  x19, x17, fail                     # it round-tripped as a real capability

    # ═══ ROW E -- ANTI-REGRESSION: the DATA family still reaches the device
    #             (increment 1). A read only -- writing CLINT offset 0 would
    #             raise a software interrupt. ═══════════════════════════════
    li   x20, 0
    .insn r 0x0b, 0x3, 0x00, x20, x9, x8    # ocl.d x20, c9, x8 -- reads the CLINT
    li   x17, 2
    bne  x27, x17, fail                     # and it did NOT trap

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
ram:
    .space 64
