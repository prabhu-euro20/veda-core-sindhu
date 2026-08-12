.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_02 (Phase 2, increment 1) -- OBJECT RESIDENCY.
#
# Binding an object whose CONTENTS are not in memory must raise an explicit,
# bounded VEDA_CAUSE_RESIDENCY_FAULT (0x0A) and mint nothing. This is
# object-granular demand paging: the handler would fetch from `backing`,
# allocate a physical Base via ODT-Populate-Fast, set resident, and retry.
#
# Object_ID 600 is reset-seeded valid with sane Base/Length/Perms but
# resident = false. It cannot be produced at runtime -- Populate is the
# instruction that establishes residency -- which is why it is seeded.
#
# THREE things are asserted, and the second and third are the load-bearing
# ones, because a fault alone proves very little here:
#
#  1. cause is 0x0A -- NOT 0x05 (OBJECT_NOT_FOUND). That distinction is the
#     entire point: not-found means the object never existed and the caller
#     should give up; a residency fault means it exists and is merely absent,
#     so the pager should fetch it and the access should be retried. A
#     handler that cannot tell these apart cannot page.
#  2. mepc points at the faulting Bind ITSELF, not past it. A residency fault
#     must be RESUMABLE -- the whole mechanism depends on re-executing the
#     instruction after the object is paged in. This is what distinguishes a
#     pager fault from every other Veda trap in the model.
#  3. the destination capability is left COMPLETELY untouched -- not even Tag
#     cleared -- so a faulting bind mints nothing a compartment could use.
#
# Expected mtval = cap_idx << 5 | cause = (0 << 5) | 0x0A = 0x0A (rd = c0).
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 600
fault_instr:
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1 -- must RESIDENCY_FAULT

    RVMODEL_HALT_FAIL              # reached only if the bind wrongly resolved

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18                  # E_Extension (every Veda hard trap)
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x0A                  # cause 0x0A (RESIDENCY_FAULT), cap_idx 0
    bne  t3, t4, fail

    # (2) RESUMABILITY: mepc must point at the faulting Bind itself.
    csrr t3, mepc
    la   t4, fault_instr
    bne  t3, t4, fail

    # (3) nothing minted: c0 untouched, tag still clear, base still zero.
    .insn r 0x5b, 0x0, 0x03, x5, x0, x0   # cgettag  x5, c0 -- expect 0
    bnez x5, fail
    .insn r 0x5b, 0x0, 0x00, x6, x0, x0   # cgetbase x6, c0 -- expect 0
    bnez x6, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
