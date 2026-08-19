.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R87 -- THE SHIPPED SWITCHER, NOW INSIDE THE VERIFICATION GATE AND PASSING.
#
# runtime/veda_sched_asm.S is cited across DESIGN_07 as "the shipped switcher" --
# the real software that must keep working, and therefore the honest price of a
# mechanism. NOTHING BUILT IT: four grep hits and all four comments; four suites
# and none of them; one script that does, assembling with an llvm-mc that is not
# on this machine. Its first execution ever, through this driver, TRAP-LOOPED.
#
# FIVE STALE ASSUMPTIONS, FROM FIVE DIFFERENT LANDINGS, each found by fixing the
# one before it and re-running -- the failure moved exactly where predicted:
#   1  save areas were 48 bytes with a 16-byte capability slot: a 128-BIT layout.
#      A Veda capability is 256 bits, so OCS.C writes 32. Now 64 bytes, .align 5.
#   2  their Perms were 0x000C. R40 made LOAD_CAP/STORE_CAP enforced. Now 0x003C.
#   3  no csrw 0x8CA anywhere. R71 clears the capability file at a crossing and
#      trap entry zeroes the mask, so c6/c7/c8 were cleared out from under it.
#   4  the return sentry used Length 0xFFFF, "unbounded" when Length was 16 bits.
#      It is 40 now, so that was a real 65535-byte compartment -- and PLAIN
#      POPULATE CANNOT EXPRESS THE FIX, its descriptor carrying only 16 bits of
#      Length by deliberate encoding limit. The site had to become populate.fast.
#   5  R75/R76 made ambient creation stamp VEDA_DOMAIN_BOOT. The thread code
#      objects are populated from boot but BOUND after an OCReturn, which names
#      PCC with the sentry's object -- so the domain arm refused. Measured:
#      mcause 0x18, mtval 0x18b = cap_idx 12, cause 0x0B DOMAIN_VIOLATION.
#      Both test mirrors declare region 0; the shipped file declared nothing.
#
# EVERY ONE was absorbed by the two self-contained test mirrors and by nothing
# else. From here on, a change that breaks the switcher breaks a suite.
#
# Every register by NUMBER except the ABI-mandated argument registers.
_start:
    la   sp, driver_stack_top

    la   a0, thread0                 # entry0
    li   a1, 8                       # len0 -- two instructions
    la   a2, thread1                 # entry1
    li   a3, 8                       # len1
    call veda_sched_init_asm

    li   a0, 4                       # four yields, then return to us
    call veda_sched_run_asm

    li   x20, 4
    bne  a0, x20, fail               # the switcher reached exactly four yields
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

# The two threads. Each runs inside its own OCInvoke-narrowed compartment with
# Execute only, so it may do nothing but yield -- which is all a round-robin
# smoke needs, and all an 8-byte Execute window allows.
.balign 4
thread0:
    ecall
    j    thread0
.balign 4
thread1:
    ecall
    j    thread1

.section .data
.balign 16
driver_stack:
    .space 256
driver_stack_top:

.include "../runtime/veda_sched_asm.S"
