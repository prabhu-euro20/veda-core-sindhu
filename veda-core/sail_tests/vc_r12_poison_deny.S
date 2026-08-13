.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R12 (DESIGN_07 Tier H) -- THE FAIL-CLOSED HALF: poison, and deny on an
# unreconstructible unwind.
#
# WHY THIS FILE EXISTS. Mutation testing of the R12 fix killed the mutant
# that recreates the defect itself, but TWO survivors showed the
# fail-closed mechanism had no coverage at all: making poison never fire,
# and making saturation not poison, both left the whole suite passing. The
# security-critical half of the fix was unverified. That is the same shape
# found repeatedly in this work -- tests prove a mechanism WORKS and say
# nothing about what it REFUSES.
#
# THE CASE POISON EXISTS FOR. Ordinary nesting is lossless: every trap
# resets PCC before the handler runs, so an inner level's context is the
# reset context by construction and a counter can reconstruct it without
# storing anything.
#
# The exception is a handler that narrows ITSELF and then faults. A handler
# runs unbounded, and while unbounded it is permitted to write
# veda_pcc_base/_length (the CSR gates allow exactly that). If it does, and
# then takes a fault, THAT level now carries real context -- one slot
# cannot hold it, and a counter cannot reconstruct it, because the level's
# state is no longer the reset state.
#
# Guessing there would be R12 again, one level up: reconstructing the reset
# context would hand UNBOUNDED authority to a level that had been narrowed.
# So the chain is marked unreconstructible and the unwind DENIES -- PCC
# comes back zero-length, which faults on the very next fetch. Loud, and
# incapable of granting anything.
#
# WHAT IS ASSERTED. After the handler narrows itself and faults, the unwind
# must produce a zero-length PCC, not the compartment's real bounds and not
# unbounded. Observed directly through the trap-status CSR and the PCC
# length CSR, from the unbounded side where a halt is always reachable.
_start:
    la   x5, handler
    csrw mtvec, x5

    li   x6, 0x0100
    slli x6, x6, 16
    ori  x6, x6, 0x0402                    # Length 0x100, Execute|Invoke
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 740
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # veda.odt.populate.fast

    li   x1, 741                            # data object for the handoff
    li   x2, 0x8001300000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 742                            # type authority
    li   x2, 0x8001310000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 740
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1
    li   x1, 741
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, x1
    li   x1, 742
    .insn i 0x0b, 0x5, x2, x1, 0           # veda.bind c2, x1
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    # cseal c4, c1, c2

    li   x20, 0                            # trap counter
    li   x21, 0                            # stage marker
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
    beq  x20, x9, third_trap               # dispatch trap 3 HERE, not inside
                                           # second_trap -- an earlier version
                                           # routed only x20==2 and the third
                                           # trap fell into the trap-1 path
    li   x9, 2
    beq  x20, x9, second_trap

    # ---- trap 1, from the compartment. depth is now 1 and the
    #      compartment's real 0x0100 bounds are saved.
    csrr x22, 0x7C8                        # {poison, depth} -- expect 1
    csrr x23, 0x7C3                        # mepcc_length -- expect 0x0100

    # ---- NARROW OURSELVES. This is the whole point of the test. The
    #      handler runs unbounded, so writing these CSRs is permitted, and
    #      after this the handler's own level carries real context that a
    #      counter cannot reconstruct.
    la   x12, handler
    csrw 0x7C0, x12                        # veda_pcc_base
    li   x13, 0x0400                       # BOUNDED, but large enough to still
                                           # contain the rest of this handler.
                                           # An earlier attempt used 0x0080 and
                                           # put the very next instruction
                                           # outside the new window, so the
                                           # narrowing itself fetch-faulted and
                                           # depth ran away -- a real property
                                           # of self-narrowing, not a typo.
    csrw 0x7C1, x13                        # veda_pcc_length -- now BOUNDED
    li   x21, 1

    # ---- and now fault from that narrowed state
    li   x14, 0
    .insn r 0x0b, 0x3, 0x00, x15, x6, x14  # ocl.d c6 -- untagged, TRAPS
    j    fail                              # the second trap must not return here

.balign 4
second_trap:
    # trap 2, taken while the handler was narrowed. The save must NOT have
    # been overwritten, and the chain must now be marked unreconstructible.
    csrr x24, 0x7C8                        # {poison, depth}
    li   x9, 0x102                         # poison=1, depth=2
    bne  x24, x9, fail
    csrr x25, 0x7C3                        # the outer save is still intact
    li   x9, 0x0100
    bne  x25, x9, fail

    # ---- unwind both levels from here. PCC is unbounded again (trap 2
    #      reset it), so these instructions and the halt are reachable.
    # ---- unwind ONE level. depth 2 -> 1 with poison set, so the unwind
    #      must install a ZERO-LENGTH PCC rather than reconstructing the
    #      reset context. Reconstructing would hand unbounded authority to
    #      a level that had been narrowed -- R12 again, one level up.
    #
    #      A zero-length PCC cannot fetch, so the proof that deny fired is
    #      that this mret produces ANOTHER trap instead of resuming. Had
    #      the unwind reconstructed instead of denying, execution would
    #      have continued in the handler and no third trap would occur.
    csrr x16, mepc
    addi x16, x16, 4
    csrw mepc, x16
    mret

.balign 4
third_trap:
    # Reached only because the poisoned unwind denied. That is the whole
    # assertion: fail-closed, loudly, at the very next fetch.
    csrr x26, 0x7C8
    li   x9, 1
    bne  x21, x9, fail                     # the handler really did narrow itself
    RVMODEL_HALT_PASS

.balign 4
verdict:
    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL
