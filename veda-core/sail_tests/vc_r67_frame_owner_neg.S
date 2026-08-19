.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R67 -- the trap frame has an OWNER, not just a count.
#
# veda_trap_frame_abandon asks "is a frame outstanding" -- a COUNT -- and never
# "is this frame mine to abandon" -- an IDENTITY. veda_trap_depth is pushed at
# exactly ONE site (trap entry) and popped at TWO (restore_on_xret and abandon),
# and OCInvoke touches it nowhere. So an OCRETURN executed by a principal that
# never trapped pops a frame it did not push.
#
# MEASURED BEFORE THE FIX, by instruction trace:
#   compartment C traps          -> depth 1, mepcc_length = 0x40  (C's window)
#   the handler OCInvokes into D -> depth still 1; D never trapped
#   D executes OCRETURN          -> depth 0, mepcc_length = 0xFFFFFFFFFF
# C's frame was gone, so any later mret would restore nothing and C could never
# be reinstated with its own bounds. After the fix the same binary reads
# depth 1 and mepcc_length 0x40 at the landing.
#
# R12's poison does NOT catch it: poison arms on a nested TRAP, and no trap
# occurred inside the handler. The handler narrowing itself by OCInvoke is the
# case R12's own comment names as real.
#
# THIS SHARPENS R12 RATHER THAN CONTRADICTING IT. R12 abandons because OCRETURN
# "installs PCC from its own operand, so any saved context is superseded by
# definition" -- true of the handler's EXIT, false of an OCRETURN that merely
# returns from a callee the handler invoked. A counter is used rather than an
# owner check because the shipped switcher deliberately OCRETURNs to a DIFFERENT
# principal than the one that trapped; requiring the target to match would break
# the one path R12 was written for.
#
# Every register by number: x27 traps, x17 handler temp, x16 phase.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x16, 0

    # authority object (Seal|Unseal)
    li   x1, 602
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # compartment C: narrow code window
    la   x6, compC
    slli x6, x6, 32
    li   x7, 0x00400402
    or   x2, x6, x7
    li   x1, 600
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 601
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # compartment D: a SECOND compartment the handler will call into
    la   x6, compD
    slli x6, x6, 32
    li   x7, 0x00400402
    or   x2, x6, x7
    li   x1, 603
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 604
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    # an unbounded sentry D returns through
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, 605
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8
    bne  x27, x0, fail

    li   x1, 602
    .insn i 0x0b, 0x5, x7, x1, 0            # authority -> c7
    li   x1, 600
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 601
    .insn i 0x0b, 0x5, x1, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7     # sealed C pair -> c3/c4
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7
    li   x1, 603
    .insn i 0x0b, 0x5, x8, x1, 0
    li   x1, 604
    .insn i 0x0b, 0x5, x9, x1, 0
    .insn r 0x5b, 0x1, 0x10, x10, x8, x7    # sealed D pair -> c10/c11
    .insn r 0x5b, 0x1, 0x10, x11, x9, x7
    li   x1, 605
    .insn i 0x0b, 0x5, x12, x1, 0
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0   # csealentry c13 -- D's exit sentry
    bne  x27, x0, fail

    csrr x18, 0x7C8                         # depth before anything: expect 0
    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4     # ocinvoke -> C
    j    fail
.balign 4
compC:
    csrr x19, 0x7C1                         # C's own PCC length -- CONTROL
    ecall                                   # depth 1, C's bounds saved
    j    fail
.balign 4
compD:
    csrr x21, 0x7C8                         # depth inside D -- still 1?
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0    # ocreturn c13 -- D never trapped
    j    fail
.balign 4
landing:
    csrr x22, 0x7C8                         # THE MEASUREMENT: depth now?
    csrr x23, 0x7C3                         # and is C's saved frame still there?
    j    check
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x20, 0x7C8                         # depth in the handler: expect 1
    csrr x24, 0x7C3                         # C's saved length
    # the handler narrows ITSELF by OCInvoke -- the case R12's own comment names
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x10, x11   # ocinvoke -> D
    j    fail
check:
    bnez x18, fail                          # CONTROL 1: depth starts at 0
    li   x14, 0x40
    bne  x19, x14, fail                     # CONTROL 2: C really is narrow
    li   x14, 1
    bne  x20, x14, fail                     # CONTROL 3: the trap pushed a frame
    li   x14, 0x40
    bne  x24, x14, fail                     # CONTROL 4: and it is C's window
    li   x14, 1
    bne  x21, x14, fail                     # inside D the frame is still outstanding
    li   x14, 1
    bne  x22, x14, fail                     # THE FINDING: D's OCRETURN must NOT
                                            # pop it. Before the fix this was 0.
    li   x14, 0x40
    bne  x23, x14, fail                     # and C's saved window must survive.
                                            # Before the fix it was 0xFFFFFFFFFF
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
