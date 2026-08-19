# Real self-check convention, reused field-for-field from this project's
# own already-verified ACT4 RVMODEL macros
# (act4-verify/config/cores/cvw/cvw-rv64gc/rvmodel_macros.h) -- not a new
# mechanism, the same one already proven to work for the RVA23 base core's
# real conformance testbench, applied here to sail_riscv_sim's own real,
# built-in HTIF support instead of a custom Verilog testbench watcher.

.section .tohost,"aw",@progbits
.balign 8
.global tohost
tohost: .dword 0
.balign 8
.global fromhost
fromhost: .dword 0
.section .text

# Two 32-bit stores at offsets 0/4, not one 64-bit store -- the real,
# exact ACT4 RVMODEL_HALT_PASS/FAIL convention (rvmodel_macros.h): low
# word = the pass/fail code, high word = 0 explicitly. Matches this
# project's own real, previously-debugged tohost write-race lesson from
# the RVA23 RTL testbench (tb_act4.sv): the two words are written as two
# separate stores, and a real watcher must treat the low-word write and
# the high-word-still-0 write as the actual "done" signal together, not
# just the first nonzero write it sees.
.macro RVMODEL_HALT_PASS
    li   x1, 1
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
self_loop_pass_\@:
    j self_loop_pass_\@
.endm

.macro RVMODEL_HALT_FAIL
    li   x1, 3
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
self_loop_fail_\@:
    j self_loop_fail_\@
.endm

# ═══ R83 -- THE PURECAP-SAFE HALT ══════════════════════════════════════════
#
# RVMODEL_HALT_PASS/FAIL above signal completion with two ORDINARY `sw` stores.
# Under purecap (veda_mode bit 0) an ordinary store is refused
# (VEDA_CAUSE_PURECAP_VIOLATION, postlude/step_ext.sail:169-176, no privilege
# exemption), so no test can END with purecap on. That is not a small detail:
# measured across the 12 files that touch 0x7C5, EIGHT enable purecap and then
# disable it again purely so they can halt -- vc_purecap_store_neg.S:27-31 says
# so in its own words. The consequence is that PURECAP'S STEADY STATE HAS NEVER
# BEEN EXECUTED by anything in this project. A mechanism that no test can leave
# switched on is a mechanism no test measures.
#
# These macros signal through a real capability instead.
#
# ONE 64-BIT OCS.D REPLACES THE TWO 32-BIT STORES, and it is strictly better
# rather than merely equivalent. The comment above explains why the original
# used two separate 32-bit stores: a watcher must see the low word and the
# high-word-zero together, and this project has been bitten by that write race
# before. OCS.D writes xlen_bytes -- 8 on RV64, veda_ocl_insts.sail:28-30 -- so
# ONE store puts the code in the low word and zero in the high word ATOMICALLY.
# The race the two-store convention worked around cannot occur.
#
# OBJECT ID 253 IS RESERVED FOR THE HARNESS, and it was chosen by measurement,
# not by taste: a scan of every literal object ID in sail_tests/, rtl/sim/,
# difftest/probes/ and runtime/ found 236 distinct values occupying 187 of the
# 256 possible low bytes. THE LOW BYTE IS WHAT MATTERS -- the RTL indexes its
# ODT with local[7:0] -- and 253 is free both as a whole value and as a low
# byte. Do not reuse it in a test.
.equ VEDA_HARNESS_TOHOST_OBJ, 253

.macro VEDA_HALT_BIND_TOHOST reg
    la   \reg, tohost
    slli \reg, \reg, 32
    li   t1, (16 << 16) | 0x000C        # Length 16 (tohost + fromhost), LOAD|STORE
    or   \reg, \reg, t1
    li   t0, VEDA_HARNESS_TOHOST_OBJ
    .insn r 0x0b, 0x0, 0x03, x5, t0, \reg   # veda.odt.populate
    li   t0, VEDA_HARNESS_TOHOST_OBJ
    .insn i 0x0b, 0x5, x14, t0, 0            # veda.bind c14
.endm

.macro RVMODEL_HALT_PASS_PURECAP
    VEDA_HALT_BIND_TOHOST t2
    li   t0, 0
    li   t1, 1
    .insn r 0x0b, 0x3, 0x01, t1, x14, t0     # ocs.d c14, t0(=0), t1(=1)
self_loop_pass_pc_\@:
    j self_loop_pass_pc_\@
.endm

.macro RVMODEL_HALT_FAIL_PURECAP
    VEDA_HALT_BIND_TOHOST t2
    li   t0, 0
    li   t1, 3
    .insn r 0x0b, 0x3, 0x01, t1, x14, t0     # ocs.d c14, t0(=0), t1(=3)
self_loop_fail_pc_\@:
    j self_loop_fail_pc_\@
.endm
