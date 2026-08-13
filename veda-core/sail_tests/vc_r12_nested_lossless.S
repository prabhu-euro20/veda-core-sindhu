.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R12 (DESIGN_07 Tier H) -- A NESTED TRAP MUST NOT DESTROY THE SAVED
# COMPARTMENT BOUNDS.
#
# THE DEFECT THIS PINS. veda_pcc_save_and_reset captured UNCONDITIONALLY,
# so a trap taken inside a trap handler copied the already-reset PCC over
# the outer compartment's saved bounds. The restore was guarded on
# veda_mepcc_length != VEDA_PCC_UNBOUNDED, which read that clobbered value
# as "nothing was ever saved" -- so it restored NOTHING and the compartment
# resumed UNBOUNDED. It failed OPEN: a privilege boundary dissolved in
# silence.
#
# WHAT IS ASSERTED NOW, and it is stronger than "safe". With the depth
# counter the nesting is LOSSLESS, not merely fail-closed: every trap
# resets PCC before the handler runs, so an inner level's context is the
# reset context by construction and can be reconstructed rather than
# stored. One slot plus a counter is therefore exact for these levels.
#
#   trap 1 from the compartment : depth 0->1, bounds saved
#   trap 2 inside the handler   : depth 1->2, nothing saved, nothing clobbered
#   inner mret                  : depth 2->1, reconstruct the reset context
#   outer mret                  : depth 1->0, restore the REAL bounds
#
# So the compartment must resume with its own 0x0100 bounds intact. Under
# the defect it resumed with 0xFFFFFFFFFF.
#
# HOW IT IS OBSERVED. The compartment cannot jump out of its own window to
# report, so after resuming it reads veda_pcc_length into x23 and issues an
# ecall; the handler -- which runs unbounded -- does the asserting. That
# also keeps every assertion on the unbounded side, where a halt is always
# reachable regardless of the compartment's bounds.
_start:
    la   x5, outer_handler
    csrw mtvec, x5

    # a bounded code object to run inside: Length 0x0100,
    # Perms = Permit_Execute(1) | Permit_Invoke(10)
    li   x6, 0x0100
    slli x6, x6, 16
    ori  x6, x6, 0x0402
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 730
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7    # veda.odt.populate.fast

    li   x1, 731                            # data object for the invoke handoff
    li   x2, 0x8001200000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 732                            # type authority
    li   x2, 0x8001210000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 730
    .insn i 0x0b, 0x5, x0, x1, 0           # veda.bind c0, x1  -- CODE
    li   x1, 731
    .insn i 0x0b, 0x5, x1, x1, 0           # veda.bind c1, x1  -- DATA
    li   x1, 732
    .insn i 0x0b, 0x5, x2, x1, 0           # veda.bind c2, x1  -- authority
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2    # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2    # cseal c4, c1, c2

    li   x20, 0                            # trap counter
    li   x21, 0                            # nested-trap-taken marker
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    # ocinvoke c3, c4 -- enter, PCC narrows
    j    fail

.balign 4
compartment:
    csrr x22, 0x7C1                        # veda_pcc_length on entry
    li   x9, 0x0100
    bne  x22, x9, fail                     # fixture sanity: genuinely bounded

    li   x10, 0
outer_fault:
    .insn r 0x0b, 0x3, 0x00, x11, x5, x10  # ocl.d c5 -- c5 untagged, TRAPS

    # Resumed by the outer handler's mret. THE ASSERTION lives here: read
    # the restored bounds and hand them to the handler via ecall, which is
    # the only way out of a 0x0100 window.
    csrr x23, 0x7C1
    ecall
    j    fail

.balign 4
outer_handler:
    addi x20, x20, 1
    # trap 3 is the compartment's ecall, carrying the verdict in x23
    li   x9, 3
    beq  x20, x9, verdict

    csrr x28, mepc                         # save our own mepc across nesting
    beq  x21, x0, take_nested              # first entry: go nest
    j    resume_outer

take_nested:
    li   x21, 2
    la   x5, inner_handler
    csrw mtvec, x5
    li   x12, 0
    .insn r 0x0b, 0x3, 0x00, x13, x6, x12  # ocl.d c6 -- untagged, TRAPS (nested)
    la   x5, outer_handler
    csrw mtvec, x5

resume_outer:
    # THE ASSERTION, made HERE rather than after resuming into the
    # compartment. Everything the lossless property claims is observable at
    # this point, and observing it here needs no assumption about the
    # resume path -- an earlier version asserted after the mret and spent a
    # long detour on a probe that was reading a register the compartment
    # never wrote.
    csrr x18, 0x7C8                        # {poison, depth}
    csrr x19, 0x7C3                        # veda_mepcc_length
    li   x9, 1
    bne  x18, x9, fail                     # depth 1, poison 0 -- the nested
                                           # level unwound, no poison set
    li   x9, 0x0100
    bne  x19, x9, fail                     # THE SAVE SURVIVED THE NESTING.
                                           # Under R12 this read the
                                           # UNBOUNDED sentinel: the nested
                                           # trap had overwritten it, and the
                                           # restore then read that as
                                           # "nothing was saved" and resumed
                                           # the compartment unbounded.
    li   x9, 2
    bne  x21, x9, fail                     # both stages really happened
    RVMODEL_HALT_PASS

    addi x28, x28, 4
    csrw mepc, x28
    mret

.balign 4
inner_handler:
    addi x20, x20, 1
    csrr x14, mepc
    addi x14, x14, 4
    csrw mepc, x14
    mret

.balign 4
verdict:
    # x23 is the compartment's PCC length after the nested trap unwound.
    # 0x0100 = the real bounds were preserved -- lossless, as designed.
    # 0xFFFFFFFFFF = the R12 defect: resumed unbounded.
    # 0 = the fail-closed deny path, which must NOT trigger here because
    #     the handler never narrowed itself.
    li   x9, 0x0100
    bne  x23, x9, fail
    li   x9, 3
    bne  x20, x9, fail                     # exactly three traps: outer, nested, ecall
    li   x9, 1
    bne  x21, x9, fail                     # the nested trap really was taken
    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL
