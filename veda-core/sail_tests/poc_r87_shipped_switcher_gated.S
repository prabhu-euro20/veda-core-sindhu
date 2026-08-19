.include "veda_selfcheck_macros.S"
.section .text
.global _start
# NOT RUN BY THE SUITE YET. The runner globs vc_*.S; this is poc_*, because IT
# DOES NOT PASS -- and what it measures is why.
#
# R87 -- THE FIRST EXECUTION OF THE SHIPPED SWITCHER, AND IT DOES NOT RUN.
#
# Measured: trap loop at MEPC=0x80000214, which disassembles to
#   0253458b  =  ocs.c c6, x5(=32), c11
# the first spill of the globals table-base capability into save area 0. TWO
# independent reasons, both stale assumptions the runtime never absorbed:
#   (i)  save_area_0's object is `li t1, 0x0030000C` -- Length 48 bytes -- and its
#        own layout comment reserves 16 bytes for the capability ("low 8B" /
#        "high 8B"). But a Veda capability is 256 BITS since the 256-bit respec
#        (veda_types.sail:102-107), so OCS.C writes 32 bytes. Offset 32 + 32 = 64
#        against a 48-byte object: BOUNDS_VIOLATION.
#   (ii) those Perms are 0x000C = LOAD|STORE. PERM_LOAD_CAPABILITY (bit 4) and
#        PERM_STORE_CAPABILITY (bit 5) are absent, and R40 made both enforced.
# Two more are latent behind it -- see DESIGN_07 R87.
#
# runtime/veda_sched_asm.S is cited across DESIGN_07 as "the shipped switcher" --
# the real software that must keep working, and therefore the honest price of a
# mechanism. R72 priced the copy-on-write carry bit against its save areas, R77
# noted it OCInvokes from inside the handler, R83 counted its 13 ordinary
# loads/stores as what purecap would cost.
#
# NOTHING BUILT IT. Verified four ways: no suite test includes it (four grep hits,
# all comments); verification.sh runs four scripts and none builds it; the one
# script that does assembles with toolchain/llvm-project/build/bin/llvm-mc, and
# llvm-project is ABSENT; and no built ELF anywhere contains saved_ra or saved_sp.
#
# THE LLVM DEPENDENCY WAS UNNECESSARY. Every Veda instruction in that file is a
# .insn, so the GNU assembler the other four suites already use handles it with
# no errors and no undefined symbols -- it exports exactly veda_sched_init_asm
# and veda_sched_run_asm and requires nothing.
#
# So this test simply INCLUDES the real file and drives it. From here on, a change
# that breaks the switcher breaks a suite.
#
# WHAT IT ASSERTS: the switcher initialises two thread code objects, runs the
# cooperative round-robin for a fixed number of yields, and returns the yield
# count it actually reached. Reaching `verdict` at all proves the whole
# trap/OCInvoke/OCReturn/TSC cycle completed the requested number of times.
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
