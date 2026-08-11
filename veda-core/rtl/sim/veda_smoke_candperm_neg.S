.section .text
.global _start
# RTL mirror of Sail vc_candperm_neg -- attenuating a SEALED capability
# soft-fails (Tag cleared). The seal authority is minted at runtime as
# Object_ID 10 (the RTL reset-seed, unlike Sail's, does not provide a
# seal-permission object), mirroring veda_smoke_m6.S's proven sequence.
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1   (target, perms 0x100C)

    li   x1, 10
    li   x2, 0x8001020000400300          # Base 0x80010200, Len 0x40, Perms 0x0300 (Seal|Unseal)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  (mint authority Object_ID 10)
    li   x1, 10
    .insn i 0x0b, 0x5, x2, x1, 0         # veda.bind c2, x1   (authority, otype = Offset = 0)

    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2   (c1 sealed otype 0, tag 1)
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0 # cgettag  x10, c1   -> 1
    .insn r 0x5b, 0x0, 0x04, x11, x1, x0 # cgettype x11, c1   -> 0 (really sealed, otype 0)

    li   x2, 0x000C
    .insn r 0x5b, 0x1, 0x17, x2, x1, x2  # candperm c2, c1, x2 (attenuate the SEALED c1)
    .insn r 0x5b, 0x0, 0x03, x12, x2, x0 # cgettag  x12, c2   -> 0 (sealed source soft-fails)
1:  j 1b
