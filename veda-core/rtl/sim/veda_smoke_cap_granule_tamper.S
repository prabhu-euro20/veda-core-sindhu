.section .text
.global _start
# RTL mirror of Sail vc_cap_granule_tamper_neg -- THE security property behind
# widening the tag granule to 32 bytes. A stored capability's second 16 bytes
# hold Perms/otype/generation. With a 16-byte granule, an ordinary store into
# that half would clear only the SECOND granule's tag while the load keeps
# reading the FIRST -- so the capability would load back VALID with rewritten
# permissions: a forgery. With a 32-byte granule the tampering store lands in
# the same granule the load checks, so the tag is gone.
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  (Base 0x80010000, Len 0x40)

    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x0, x0, x2  # ocs.c c0, x2(=0), c0   -- store the capability
    .insn r 0x0b, 0x4, 0x00, x1, x0, x2  # ocl.c c0, x2(=0), c1   -- round-trips tagged?
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0 # cgettag x10, c1        -- expect 1

    li   x3, 16
    li   x4, 0x4141414141414141
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3(=16), x4  -- ORDINARY store into byte 16

    .insn r 0x0b, 0x4, 0x00, x2, x0, x2  # ocl.c c0, x2(=0), c2   -- reload from offset 0
    .insn r 0x5b, 0x0, 0x03, x11, x2, x0 # cgettag x11, c2        -- expect 0 (tamper destroyed it)
1:  j 1b
