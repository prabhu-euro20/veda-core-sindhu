.include "veda_selfcheck_macros.S"
.section .text
.global _start
# PoC -- DOES A NESTED TRAP DESTROY THE SAVED COMPARTMENT BOUNDS?
#
# THE ASYMMETRY THAT PROMPTED THIS. veda_pcc_save_and_reset does two
# captures in one function. The CRBR half is GUARDED:
#     if veda_current_region != zeros() then { save }
# so a second trap taken inside a handler, where the region has already
# been reset to root, does not overwrite the outer save. The PCC half
# directly above it has NO guard at all -- it copies unconditionally.
#
# If that matters, then on a nested trap the PCC save captures the
# already-reset value {base = 0, length = UNBOUNDED} and destroys the
# outer compartment's saved bounds. The restore is guarded on
#     veda_mepcc_length != VEDA_PCC_UNBOUNDED
# which reads exactly that clobbered value as "nothing was ever saved",
# so it restores NOTHING and the compartment resumes UNBOUNDED.
#
# That direction matters. Clobbering mepc in ordinary RISC-V is loud --
# the handler returns somewhere wrong. Clobbering mepcc this way is
# silent and it fails OPEN: the compartment keeps running, with its
# bounds removed.
#
# HALT_PASS here means THE PROBLEM IS REAL: PCC came back unbounded after
# a nested trap. HALT_FAIL means the bounds were preserved and there is
# nothing to fix.
_start:
    la   t0, outer_handler
    csrw mtvec, t0

    # ---- a bounded code object to run inside: Base = compartment,
    #      Length = 0x0100, Perms = Permit_Execute(1) | Permit_Invoke(10)
    li   t1, 0x0100
    slli t1, t1, 16
    ori  t1, t1, 0x0402
    csrw 0x7C4, t1
    la   t2, compartment
    li   x1, 720
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2  # veda.odt.populate.fast

    # ---- a data object for the invoke handoff
    li   x1, 721
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate

    # ---- type authority
    li   x1, 722
    li   x2, 0x80010A0000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate

    li   x1, 720
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1   -- CODE
    li   x1, 721
    .insn i 0x0b, 0x5, x1, x1, 0         # veda.bind c1, x1   -- DATA
    li   x1, 722
    .insn i 0x0b, 0x5, x2, x1, 0         # veda.bind c2, x1   -- authority
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    li   x20, 0                          # trap counter
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- enter, PCC narrows
    j    fail                            # crossing must have jumped

.balign 4
compartment:
    # Running with PCC narrowed to {compartment, 0x0100}. Confirm that.
    csrr x21, 0x7C1                      # veda_pcc_length
    li   t1, 0x0100
    bne  x21, t1, fail                   # fixture sanity: we are bounded

    # Take trap #1 from inside the compartment. c5 was never bound, so
    # this is an ordinary untagged-capability violation.
    li   x22, 0
outer_fault:
    .insn r 0x0b, 0x3, 0x00, x10, x5, x22  # ocl.d c5 -- TRAPS (untagged)

    j    fail                            # the outer handler halts; never resumed

.balign 4
outer_handler:
    # Trap #1. mepcc now holds the compartment's real bounds.
    addi x20, x20, 1
    csrr x24, 0x7C3                      # veda_mepcc_length -- should be 0x0100
    csrr x28, mepc                       # save mepc ourselves, as any
                                         # handler taking nested traps must

    # ---- NOW TAKE A SECOND TRAP, from inside the handler. This is the
    #      whole experiment. A handler running with unbounded PCC that
    #      touches an untagged capability is an entirely ordinary thing
    #      for a pager or scheduler to do.
    li   x29, 0
    la   t0, inner_handler
    csrw mtvec, t0
    .insn r 0x0b, 0x3, 0x00, x11, x6, x29  # ocl.d c6 -- TRAPS again (nested)

    # ---- back from the nested trap. Read mepcc again and decide HERE,
    #      in the handler, where PCC is unbounded and a halt is reachable.
    #
    #      The first version of this PoC tried to mret back into the
    #      compartment and branch on the restored PCC length. That cannot
    #      work: the two outcome labels sit outside the compartment's
    #      0x0100 window, so if the bounds were PRESERVED the compartment
    #      could not reach either of them and the model fetch-faulted in a
    #      loop. A test that can only report one of its two outcomes is not
    #      a test. Observing mepcc directly is both simpler and stronger --
    #      it measures the mechanism rather than a downstream symptom.
    csrr x25, 0x7C3                      # veda_mepcc_length AFTER the nested trap
    li   t1, 2
    bne  x20, t1, fail                   # exactly two traps were taken
    li   t1, 0x0100
    bne  x24, t1, fail                   # before: the compartment's real bounds
    li   t1, 0xFFFFFFFFFF
    beq  x25, t1, escaped                # after: clobbered to the sentinel
    li   t1, 0x0100
    beq  x25, t1, preserved              # after: survived intact
    j    fail

.balign 4
inner_handler:
    # Trap #2. Just step over the faulting instruction and return.
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

.balign 4
escaped:
    # The saved compartment bounds were destroyed by the nested trap, and
    # the restore guard will read the sentinel as "nothing was saved".
    RVMODEL_HALT_PASS

.balign 4
preserved:
    RVMODEL_HALT_FAIL

fail:
    RVMODEL_HALT_FAIL
