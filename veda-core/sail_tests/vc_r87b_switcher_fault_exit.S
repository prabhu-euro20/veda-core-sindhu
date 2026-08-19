.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R87b -- THE SWITCHER REPORTS AN UNEXPECTED FAULT INSTEAD OF SPINNING.
#
# runtime/veda_sched_asm.S's trap guard used to be `bne x28, x29, switcher_entry`
# -- a branch to ITSELF -- with the comment "not our ecall -- ignore (real fault
# recovery out of scope this pass)". Any trap that was not the scheduler's own
# ECALL spun the machine forever with mcause/mtval/mepc unread.
#
# THAT COST A WHOLE DEBUGGING CYCLE, MEASURED: when this file was first executed
# at all (R87) it stopped five times, and the fifth was undiagnosable until a
# scratch build replaced the spin with a reporting path.
#
# The guard now records the fault and returns to its caller with 0xFFFFFFFF,
# which no real yield count can be. This file makes a thread fault deliberately
# and checks all four things -- and checking the SPECIFIC cause and the EXACT
# faulting PC is what stops a machine that reported something, anything, from
# passing.
#
#   A  veda_sched_run_asm returns 0xFFFFFFFF, not a yield count
#   B  fault_cause is 0x18, the Veda trap cause
#   C  fault_tval is (17 << 5) | 0x07 -- cap_idx 17, VEDA_CAUSE_PURECAP_VIOLATION.
#      An ordinary load inside an OCInvoke-narrowed compartment is refused by
#      ext_data_get_addr's second arm whether or not veda_mode is set, and 17 is
#      that path's own out-of-range cap_idx sentinel.
#   D  fault_epc is the EXACT address of the faulting instruction
#
# The companion file vc_r87_shipped_switcher_gated.S is the anti-vacuity control:
# it runs the same switcher with well-behaved threads and gets 4 back, so a
# switcher that always reported a fault could not pass both.
_start:
    la   sp, driver_stack_top

    la   a0, faulting_thread
    li   a1, 8
    la   a2, faulting_thread
    li   a3, 8
    call veda_sched_init_asm

    li   a0, 4
    call veda_sched_run_asm

    li   x20, -1
    bne  a0, x20, fail                  # ROW A

    la   x21, fault_cause
    ld   x22, 0(x21)
    li   x23, 0x18
    bne  x22, x23, fail                 # ROW B

    ld   x22, 8(x21)
    li   x23, (17 << 5) | 0x07
    bne  x22, x23, fail                 # ROW C

    ld   x22, 16(x21)
    la   x23, faulting_thread
    bne  x22, x23, fail                 # ROW D -- the exact faulting PC

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

# An Execute-only 8-byte compartment. The ordinary load is refused because PCC is
# narrowed -- which is precisely a fault the switcher did not expect.
.balign 4
faulting_thread:
    ld   x1, 0(x0)
    j    faulting_thread

.section .data
.balign 32
driver_stack:
    .space 256
driver_stack_top:

.include "../runtime/veda_sched_asm.S"
