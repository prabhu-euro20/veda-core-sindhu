.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: ODT generation retirement at the widened
    # 24-bit generation counter (Phase 1 increment 4). Original bug (RTL
    # Milestone 16, ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2): a finite
    # generation counter wraps after enough destroy/re-populate cycles and
    # revives a stale capability's cached value; the fix retires the slot
    # once the counter saturates so it can never be reused.
    #
    # At 8 bits the threshold was 256 and the original test reached it with
    # `.rept 256`. At 24 bits the threshold is 16,777,215 -- a loop to it is
    # not a test. Instead Object_ID=55 is seeded ONE below the real threshold
    # (generation = 0xFFFFFE, via veda_test_seed_odt's reset scaffold -- the
    # same direct-state-injection the model already uses for every seeded
    # object, and the RTL uses for the owner-hart tests it has no second hart
    # to drive). Two real destroys then cross the GENUINE 24-bit boundary:
    #   Destroy #1: 0xFFFFFE -> 0xFFFFFF (saturated, not yet retired)
    #   Destroy #2: counter already at max -> slot retired
    # This proves, at the true width, exactly what the loop used to: the
    # re-populate is refused (Illegal_Instruction, mcause=2), and the stale
    # capability still hard-traps (Tag Violation, cause 0x02).

    # Bind c0 to the seeded, near-threshold object -- c0 caches generation
    # 0xFFFFFE. (The seed is valid and unowned, so the bind claims it.)
    li   x1, 55
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1

    # Two destroys: saturate, then retire.
    li   x1, 55
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy x9, x1  (#1 -> 0xFFFFFF)
    li   x1, 55
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy x9, x1  (#2 -> retired)

    # The slot is now permanently retired -- this re-populate MUST be refused.
    la   t0, retire_trap_handler
    csrw mtvec, t0
    li   x5, 0x80020100
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 55
    mv   x2, x5
repopulate_instr:
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (must be REFUSED)

    RVMODEL_HALT_FAIL          # reached only if the repopulate above wrongly succeeded

.balign 4
retire_trap_handler:
    csrr t3, mcause
    li   t4, 2                 # standard RISC-V Illegal Instruction
    bne  t3, t4, check_fail
    csrr t3, mepc
    la   t4, repopulate_instr
    bne  t3, t4, check_fail

    # Second real check: the ORIGINAL, stale c0 (never re-bound since the
    # very first bind) must still correctly hard-trap when used directly --
    # the slot stayed invalid, since the repopulate above was refused.
    addi t3, t3, 4
    csrw mepc, t3
    la   t0, stale_trap_handler
    csrw mtvec, t0
    li   x2, 0
fault_instr:
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0

    RVMODEL_HALT_FAIL          # reached only if the stale access wrongly succeeded

.balign 4
stale_trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x02              # cause=0x02 (Tag Violation), cap_idx=0 (c0)
    bne  t3, t4, check_fail

    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
