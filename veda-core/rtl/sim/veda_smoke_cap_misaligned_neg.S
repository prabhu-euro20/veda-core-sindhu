.section .text
.global _start
# RTL mirror of Sail vc_cap_misaligned_neg -- OCL.C/OCS.C require 32-byte
# natural alignment, enforced as a HARD trap (cause 0x08). Offset 16 is chosen
# deliberately: it is still fully IN BOUNDS (16 + 32 = 48 <= Length 0x40), so
# the trap must come from the alignment rule itself, not from a bounds check.
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1
    li   x2, 16
    .insn r 0x0b, 0x4, 0x01, x0, x0, x2  # ocs.c c0, x2(=16), c0 -- misaligned, must trap
    li   x20, 0xBAD                       # reached only if the store wrongly succeeded
1:  j 1b
.balign 4
trap_handler:
    csrr x10, mcause                      # expect 0x18 (E_Extension)
    csrr x11, mtval                       # expect 0x08: cap_idx=0 (c0), cause=0x08
2:  j 2b
