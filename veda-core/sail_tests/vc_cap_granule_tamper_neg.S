.include "veda_selfcheck_macros.S"
.section .text
.global _start
# The security property that motivated widening the tag granule to 32 bytes
# (DESIGN_01 decision 1). A 256-bit capability occupies 32 bytes in memory,
# and its LOW half (bytes 16..31) holds Perms, otype and generation. The tag
# is read as a single bit at the access's own granule, so with a 16-byte
# granule a plain store into bytes 16..31 would clear only the SECOND
# granule's tag while the load kept reading the FIRST granule's -- still 1.
# That would load a capability with attacker-rewritten permissions, an
# unsealed otype and a reset generation, all with a valid tag: a complete
# forgery primitive. With a 32-byte granule the tampering store lands in the
# same granule the load checks, so the tag is gone and the reload is untagged.
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1

    # Store the (tagged) capability c0 into its own object at offset 0.
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x0, x0, x2  # ocs.c c0, x2(=0), c0

    # Sanity: it round-trips through the new 256-bit memory format tagged.
    .insn r 0x0b, 0x4, 0x00, x1, x0, x2  # ocl.c c1, c0, x2
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0 # cgettag x10, c1
    li   x20, 1
    bne  x10, x20, fail

    # Tamper: an ORDINARY data store into byte 16 of the stored capability --
    # the half carrying Perms/otype/generation. No capability instruction is
    # involved, so nothing here is privileged or special.
    li   x3, 16
    li   x4, 0x4141414141414141
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3(=16), x4

    # Reload from offset 0. The tag MUST be gone.
    .insn r 0x0b, 0x4, 0x00, x2, x0, x2  # ocl.c c2, c0, x2
    .insn r 0x5b, 0x0, 0x03, x11, x2, x0 # cgettag x11, c2
    bne  x11, x0, fail                   # KEY: tampered capability is untagged

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
