.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Bind c0 to Object_ID 1 (the reset-seeded object), tagged + unsealed.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0        # veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x02, x10, x0, x0 # cgetperm x10, c0  (original Perms)
    .insn r 0x5b, 0x0, 0x00, x14, x0, x0 # cgetbase x14, c0
    .insn r 0x5b, 0x0, 0x01, x15, x0, x0 # cgetlen  x15, c0

    # --- Partial mask: verify the exact AND semantic + fields untouched ---
    li   x2, 0x0008
    .insn r 0x5b, 0x1, 0x17, x1, x0, x2  # candperm c1, c0, x2
    .insn r 0x5b, 0x0, 0x02, x11, x1, x0 # cgetperm x11, c1
    and  x20, x10, x2                    # expected = original & mask
    bne  x11, x20, fail                  # c1.Perms == c0.Perms & mask
    .insn r 0x5b, 0x0, 0x03, x13, x1, x0 # cgettag  x13, c1
    li   x20, 1
    bne  x13, x20, fail                  # tag preserved (unsealed source)
    .insn r 0x5b, 0x0, 0x00, x16, x1, x0 # cgetbase x16, c1
    bne  x16, x14, fail                  # Base unchanged by attenuation
    .insn r 0x5b, 0x0, 0x01, x17, x1, x0 # cgetlen  x17, c1
    bne  x17, x15, fail                  # Length unchanged by attenuation

    # --- Mask 0: clear ALL perms; tag must survive (attenuate != invalidate) ---
    .insn r 0x5b, 0x1, 0x17, x3, x0, x0  # candperm c3, c0, x0  (mask = 0)
    .insn r 0x5b, 0x0, 0x02, x12, x3, x0 # cgetperm x12, c3
    bne  x12, x0, fail                   # every permission cleared
    .insn r 0x5b, 0x0, 0x03, x18, x3, x0 # cgettag  x18, c3
    li   x20, 1
    bne  x18, x20, fail                  # tag still set (rights removed, cap still valid)

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
