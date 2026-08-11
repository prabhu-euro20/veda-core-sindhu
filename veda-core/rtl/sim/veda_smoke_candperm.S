.section .text
.global _start
# RTL mirror of Sail vc_candperm (positive) -- CAndPerm rights attenuation.
# Object_ID 1 is seeded with Perms 0x100C, Base 0x80010000, Length 0x40.
# Masking Perms can only clear bits; Base/Length/Tag are untouched, and even
# masking everything away leaves the capability valid (weaker, not destroyed).
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1   (perms 0x100C)
    .insn r 0x5b, 0x0, 0x02, x10, x0, x0 # cgetperm x10, c0   -> 0x100C (original)

    li   x2, 0x000C
    .insn r 0x5b, 0x1, 0x17, x1, x0, x2  # candperm c1, c0, x2 (mask 0x000C)
    .insn r 0x5b, 0x0, 0x02, x11, x1, x0 # cgetperm x11, c1   -> 0x000C (0x100C & 0x000C)
    .insn r 0x5b, 0x0, 0x03, x12, x1, x0 # cgettag  x12, c1   -> 1 (attenuation keeps the tag)
    .insn r 0x5b, 0x0, 0x00, x13, x1, x0 # cgetbase x13, c1   -> 0x80010000 (base untouched)

    .insn r 0x5b, 0x1, 0x17, x2, x0, x0  # candperm c2, c0, x0 (mask 0 -- clear everything)
    .insn r 0x5b, 0x0, 0x02, x14, x2, x0 # cgetperm x14, c2   -> 0 (all perms gone)
    .insn r 0x5b, 0x0, 0x03, x15, x2, x0 # cgettag  x15, c2   -> 1 (STILL valid: weaker != destroyed)
1:  j 1b
