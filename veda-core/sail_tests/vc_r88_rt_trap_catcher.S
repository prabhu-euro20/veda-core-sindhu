.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R88 -- runtime/veda_rt_trap_catcher.S, NOW INSIDE THE VERIFICATION GATE.
#
# R87 found that runtime/veda_sched_asm.S was built by nothing and had drifted
# five separate ways. Asking what ELSE was in that position turned up 38 of 312
# .S files unreachable by any suite. This is the one other runtime file that can
# be gated with the assembler the four suites already use: measured, it assembles
# with riscv64-unknown-elf-as and has ZERO undefined symbols.
#
# The other two cannot, and the reason is worth writing down rather than
# guessing at:
#   runtime/veda_rt_asm.S  uses real MNEMONICS -- `veda.odt.populate.fast`,
#                          `cgettag`, `ocl.d`, `veda.bind` -- not `.insn`, so it
#                          needs LLVM's +xveda assembler, which is absent here.
#                          veda_sched_asm.S was gateable precisely because it
#                          used .insn throughout.
#   runtime/crt0.S         needs main / _stack_top / __bss_start / __bss_end,
#                          i.e. the C runtime, so it needs clang.
#
# WHAT THIS CATCHER IS FOR, in its own words: every other trap handler in this
# corpus "halts permanently from inside the handler -- reaching the handler
# correctly IS their terminal pass condition." This one must catch ONE expected
# hard trap, record it, and RESUME, so a C main() can keep running. That resume
# is the property worth gating, and nothing was gating it.
#
#   A  the catcher installs itself and clears its flag        g_trap_fired == 0
#   B  a deliberate hard trap sets the flag and records mcause
#   C  and EXECUTION RESUMES -- the instruction after the faulting one runs.
#      Without C this file would pass on a catcher that never returned, which is
#      the one thing this catcher exists to do differently from all the others.
#   D  CONTROL: the recorded mcause is the SPECIFIC expected one, not merely
#      nonzero.
_start:
    call veda_rt_trap_catcher_install

    la   x5, g_trap_fired
    lw   x6, 0(x5)
    bnez x6, fail                       # ROW A -- installed clean

    # A deliberate hard trap: veda.bind of an Object_ID that was never
    # populated. R73 makes plain Bind trap loudly, and OBJECT_NOT_FOUND is 0x05.
    li   x20, 0
    li   x1, 900
    .insn i 0x0b, 0x5, x2, x1, 0        # veda.bind c2, 900 -- must hard-trap
    li   x20, 0xC0DE                    # ROW C -- reached only if it RESUMED

    la   x5, g_trap_fired
    lw   x6, 0(x5)
    li   x7, 1
    bne  x6, x7, fail                   # ROW B

    li   x7, 0xC0DE
    bne  x20, x7, fail                  # ROW C

    la   x5, g_trap_mcause
    ld   x6, 0(x5)
    li   x7, 0x18
    bne  x6, x7, fail                   # ROW D -- the Veda trap cause

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL

.include "../runtime/veda_rt_trap_catcher.S"
