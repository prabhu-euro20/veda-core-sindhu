.section .text
.global _start
# R2b: proves the 256-BIT pack/unpack is field-exact, which zero-regression
# alone cannot show (every existing test reads through CGet*, and those return
# the same numeric values under wider zero-extends whether or not the new
# layout is right). A capability is stored to memory and reloaded, and EVERY
# field is compared before vs after -- if any bit range in the 256-bit layout
# were off by even one position, some field would come back wrong.
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1
    li   x2, 0x18
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2  # oca c1, c0, x2  (nonzero Offset 0x18 -- a field
                                          #  that sits mid-layout, so a shifted unpack shows up)
    # snapshot c1's fields BEFORE the memory round-trip
    .insn r 0x5b, 0x0, 0x00, x10, x1, x0 # cgetbase   x10, c1
    .insn r 0x5b, 0x0, 0x01, x11, x1, x0 # cgetlen    x11, c1
    .insn r 0x5b, 0x0, 0x02, x12, x1, x0 # cgetperm   x12, c1
    .insn r 0x5b, 0x0, 0x04, x13, x1, x0 # cgettype   x13, c1
    .insn r 0x5b, 0x0, 0x06, x14, x1, x0 # cgetoffset x14, c1

    li   x3, 0                            # 32-byte aligned slot
    .insn r 0x0b, 0x4, 0x01, x1, x0, x3  # ocs.c c0, x3(=0), c1   -- store the 256-bit image
    .insn r 0x0b, 0x4, 0x00, x2, x0, x3  # ocl.c c0, x3(=0), c2   -- load it back

    # snapshot c2's fields AFTER
    .insn r 0x5b, 0x0, 0x00, x15, x2, x0 # cgetbase   x15, c2
    .insn r 0x5b, 0x0, 0x01, x16, x2, x0 # cgetlen    x16, c2
    .insn r 0x5b, 0x0, 0x02, x17, x2, x0 # cgetperm   x17, c2
    .insn r 0x5b, 0x0, 0x04, x18, x2, x0 # cgettype   x18, c2
    .insn r 0x5b, 0x0, 0x06, x19, x2, x0 # cgetoffset x19, c2
    .insn r 0x5b, 0x0, 0x03, x20, x2, x0 # cgettag    x20, c2  -- must still be 1
1:  j 1b
