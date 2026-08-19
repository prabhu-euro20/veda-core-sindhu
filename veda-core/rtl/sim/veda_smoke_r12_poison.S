.section .text
.global _start
# RTL-8 (R12, DESIGN_07 Tier H): THE FAIL-CLOSED HALF -- poison, and deny
# on an unreconstructible unwind.
#
# Mirrors the Sail test vc_r12_poison_deny.S.
#
# WHY THIS FILE EXISTS. The RTL-8 mutation sweep killed the mutants that
# recreate R12 itself -- unguarding the capture (the Sail half) and
# consuming on any mret (the RTL half) -- but TWO survived: making poison
# never fire, and making a poisoned unwind restore instead of deny. So the
# security-critical half of the fix was carried but unverified. That is the
# same shape found at every layer of this work: tests prove a mechanism
# WORKS and say nothing about what it REFUSES.
#
# THE CASE POISON EXISTS FOR. Ordinary nesting is lossless -- every trap
# resets PCC before the handler runs, so an inner level's context is the
# reset context by construction and the depth counter reconstructs it
# without storing anything.
#
# The exception is a handler that narrows ITSELF and then faults. A handler
# runs unbounded, and while unbounded it may write veda_pcc_base/_length.
# If it does and then faults, that level carries real context: one slot
# cannot hold it and a counter cannot reconstruct it. Guessing would hand
# UNBOUNDED authority to a level that had been narrowed -- R12 again, one
# level up. So the chain is marked unreconstructible and the unwind DENIES:
# PCC comes back zero-length, which cannot fetch.
#
# A REAL PROPERTY OF SELF-NARROWING, learned building the Sail version: the
# new window must still CONTAIN the code that keeps executing. Narrowing to
# a window that excludes the next instruction makes the narrowing itself
# fetch-fault and the depth run away. 0x0400 is chosen to cover the rest of
# this handler, not arbitrarily.
_start:
    la   x5, handler
    csrw mtvec, x5

    li   x6, 0x0100
    slli x6, x6, 16
    ori  x6, x6, 0x0402                    # Length 0x100, Execute|Invoke
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 170
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # populate.fast -- CODE

    li   x1, 171                           # DATA for the invoke handoff
    li   x2, 0x8001400000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 172                           # type authority
    li   x2, 0x8001410000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 170
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1
    li   x1, 171
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, x1
    li   x1, 172
    .insn i 0x0b, 0x5, x2, x1, 0           # veda.bind c2, x1
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    # cseal c4, c1, c2

    li   x20, 0                            # trap counter
    li   x21, 0                            # stage marker
    // R50 increment 2: this file predates the crossing's retain mask and
    // measures a different mechanism, so it declares RETAIN ALL. The burden
    // of proving the clear works sits on veda_smoke_r50i2_crossing_clear.S.
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # ocinvoke c3, c4 -- enter bounded
    j    fail

.balign 4
compartment:
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x11, x5, x10  # ocl.d c5 -- untagged, TRAPS
    j    fail

.balign 4
handler:
    addi x20, x20, 1
    li   x9, 3
    beq  x20, x9, third_trap
    li   x9, 2
    beq  x20, x9, second_trap

    # ---- trap 1, from the compartment. depth is 1 and the compartment's
    #      real 0x0100 bounds are saved.
    csrr x22, 0x7C8                        # {poison, depth}
    csrr x23, 0x7C3                        # mepcc_length

    # ---- NARROW OURSELVES. The handler runs unbounded, so these writes
    #      are permitted, and afterwards this level carries real context.
    la   x12, handler
    csrw 0x7C0, x12                        # veda_pcc_base
    li   x13, 0x0400                       # BOUNDED, and large enough to
                                           # still contain the rest of this
                                           # handler -- see the header note
    csrw 0x7C1, x13
    li   x21, 1

    li   x14, 0
    .insn r 0x0b, 0x3, 0x00, x15, x6, x14  # ocl.d c6 -- untagged, TRAPS
    j    fail

.balign 4
second_trap:
    # trap 2, taken while the handler was narrowed. The outer save must be
    # intact and the chain must now be marked unreconstructible.
    csrr x24, 0x7C8
    li   x9, 0x102                         # poison=1, depth=2
    bne  x24, x9, fail
    csrr x25, 0x7C3
    li   x9, 0x0100
    bne  x25, x9, fail                     # the outer save survived

    # ---- unwind one level. depth 2 -> 1 with poison set, so the unwind
    #      must install a ZERO-LENGTH PCC rather than reconstruct. A
    #      zero-length PCC cannot fetch, so the proof that deny fired is
    #      that this mret produces ANOTHER trap instead of resuming.
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret

.balign 4
third_trap:
    # Reached only because the poisoned unwind denied. Had it reconstructed
    # instead, execution would have continued in the handler and no third
    # trap would occur.
    li   x9, 1
    bne  x21, x9, fail
    li   x9, 0x0100
    bne  x23, x9, fail                     # trap 1 really did save the bounds
    li   x30, 0xD09E
    j    done
fail:
    li   x30, 0xBAD
done:
    j    done
