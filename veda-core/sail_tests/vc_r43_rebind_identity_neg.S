.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R43 -- "already-bound" was a precondition nobody enforced.
#
# VEDA_CORE_SPEC.md Section 4 defines Rebind as refreshing "an ALREADY-BOUND
# capability register's" fields from the ODT, leaving Offset unchanged. Neither
# half was enforced: CTag(rd) was never checked, and cur.Object_ID was never
# compared against the Object_ID in the GPR -- so Rebind would carry an Offset
# meaningful in object A onto object B's bounds.
#
# NOT an escalation as it stood: Rebind re-derives Perms from the entry and sits
# behind the same domain gate as Bind. It becomes one the moment anybody makes
# Rebind preserve the HOLDER'S Perms, which is the refuted R38(b) closure.
#
# AND CLOSING IT REMOVED THE LAST UNTAGGED SEALEDNESS READ IN THE MACHINE.
# Verified at source: OCInvoke, OCReturn, CUnseal, the dereference path, the
# CGet family and the ODA predicate all check the tag first or conjoin it.
# Rebind was the only exception -- vc_r24_crf_reset.S's own header says so.
# So the reset otype is now unobservable, and two tests that used
# Rebind-into-untagged as their discriminator are re-aimed rather than deleted.
#
# SOFT-FAIL, NOT A TRAP: Rebind never traps for any failure reason
# (Milestone 12), so the new refusals join the existing uniform soft-fail.
#
# Every register by number. x27 traps. Objects 720 and 721; c3..c9 are unseeded.
.equ OBJ_A, 720
.equ OBJ_B, 721
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0

    la   x6, arena_a
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, OBJ_A
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    la   x6, arena_b
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, OBJ_B
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x27, x0, fail

    # CONTROL 1: a genuine bind of A
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x3, x1, 0
    .insn r 0x5b, 0x0, 0x03, x18, x3, x0    # cgettag -- must be 1
    li   x8, 1
    bne  x18, x8, fail
    .insn r 0x5b, 0x0, 0x00, x19, x3, x0    # cgetbase
    la   x9, arena_a
    bne  x19, x9, fail

    # CONTROL 2: R43's POSITIVE arm -- rebinding the SAME object into a register
    # that is tagged and names it is a genuine refresh and must still succeed.
    # Without this, refusing every Rebind would pass both findings below.
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x3, x1, 2
    .insn r 0x5b, 0x0, 0x03, x20, x3, x0    # cgettag -- must still be 1
    li   x8, 1
    bne  x20, x8, fail
    .insn r 0x5b, 0x0, 0x00, x21, x3, x0
    bne  x21, x9, fail                      # and still A's Base

    # THE FINDING, part 1: a DIFFERENT object. Before the fix this succeeded and
    # carried an Offset meaningful in A onto B's bounds.
    li   x1, OBJ_B
    .insn i 0x0b, 0x5, x3, x1, 2
    .insn r 0x5b, 0x0, 0x03, x22, x3, x0    # cgettag -- must be 0
    bnez x22, fail

    # THE FINDING, part 2: an UNTAGGED destination. c4 was never written.
    li   x1, OBJ_A
    .insn i 0x0b, 0x5, x4, x1, 2
    .insn r 0x5b, 0x0, 0x03, x23, x4, x0    # cgettag -- must be 0
    bnez x23, fail

    # CONTROL 3: a refusal is a refusal, not a corruption -- a plain Bind into
    # either register still works afterwards.
    li   x1, OBJ_B
    .insn i 0x0b, 0x5, x4, x1, 0
    .insn r 0x5b, 0x0, 0x03, x24, x4, x0
    li   x8, 1
    bne  x24, x8, fail
    .insn r 0x5b, 0x0, 0x00, x25, x4, x0
    la   x10, arena_b
    bne  x25, x10, fail

    bne  x27, x0, fail                      # and nothing trapped: Rebind SOFT-fails
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.balign 64
arena_a:
    .space 64
arena_b:
    .space 64
