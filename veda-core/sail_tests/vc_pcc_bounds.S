.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: PCC compartment bounding -- Milestone 14
    # (PCC_COMPARTMENT_DESIGN.md). Proves the real state transitions: a
    # fresh hart starts unbounded; a successful OCInvoke narrows the live
    # compartment to the invoked CODE capability's own Base/Length; a
    # second OCInvoke into an unbounded return capability widens it back.
    # Fetch-time enforcement of these bounds (the actual trap) is proven
    # separately in vc_pcc_bounds_neg.S -- this file's own job is proving
    # the bookkeeping itself is correct, field-for-field, via the new
    # veda_pcc_base/veda_pcc_length CSRs (0x7c0/0x7c1).

    csrr x9, 0x7c1                # pcc_length BEFORE any OCInvoke -- expect 0xFFFFFFFFFF (VEDA_PCC_UNBOUNDED, the real reset value; Length widened 16 -> 40 bits)

    # -- Object_ID=50 (CODE): Permit_Execute|Permit_Invoke = 0x0402,
    #    Base = landing_pad's own runtime address, Length=0x0100 (256
    #    bytes -- generous headroom over landing_pad's own real code +
    #    RVMODEL_HALT_PASS's own macro expansion, the same real lesson
    #    vc_ocinvoke.S's own Milestone 14 update already learned). --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 50
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=51 (DATA): Permit_Invoke only = 0x0400. --
    li   x1, 51
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=52: type authority, Permit_Seal|Permit_Unseal = 0x0300. --
    li   x1, 52
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 50
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 51
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 52
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to Object_ID=50's own Base/Length

landing_pad:
    csrr x10, 0x7c0                # pcc_base AFTER OCInvoke -- expect landing_pad's own runtime address
    csrr x11, 0x7c1                # pcc_length AFTER OCInvoke -- expect 0x0100

    # -- Object_ID=53 (return CODE): Base=return_pad,
    #    Length=0xFFFFFFFFFF (VEDA_PCC_UNBOUNDED -- a real, deliberate
    #    "return to the unconstrained caller context" capability,
    #    Perms=0x0402). Length widened 16 -> 40 bits, so the unbounded
    #    sentinel no longer fits the compact single-GPR descriptor's own
    #    16-bit Length field (0xFFFF is now a real 65535-byte bound, not
    #    saturation) -- this object therefore has to use the WIDE populate
    #    path, Base straight from a GPR at full width and Length|Perms
    #    from veda_attr (CSR 0x7C4). The finite-Length objects above keep
    #    the compact form unchanged. --
    li   t1, 0xFFFFFFFFFF                # VEDA_PCC_UNBOUNDED
    slli t1, t1, 16                      # veda_attr = Length[55:16] | Perms[15:0]
    ori  t1, t1, 0x402                   # Permit_Execute|Permit_Invoke
    csrw 0x7C4, t1
    la   x2, return_pad                  # Base, full width, no packing/shifting
    li   x1, 53
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2

    # -- Object_ID=54 (return DATA): Permit_Invoke only = 0x0400. --
    li   x1, 54
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 53
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- return CODE
    li   x1, 54
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- return DATA

    .insn r 0x5b, 0x1, 0x10, x7, x5, x2  # cseal c7, c5, c2  -- sealed return CODE
    .insn r 0x5b, 0x1, 0x10, x8, x6, x2  # cseal c8, c6, c2  -- sealed return DATA

    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x7, x8  # ocinvoke c7, c8   -- widens PCC back to unbounded

return_pad:
    csrr x12, 0x7c1                # pcc_length AFTER the return OCInvoke -- expect 0xFFFFFFFFFF again

    li   t2, 0xFFFFFFFFFF          # VEDA_PCC_UNBOUNDED -- 40-bit Length field, all ones
    bne  x9, t2, fail
    la   t2, landing_pad
    bne  x10, t2, fail
    li   t2, 0x0100
    bne  x11, t2, fail
    li   t2, 0xFFFFFFFFFF          # VEDA_PCC_UNBOUNDED
    bne  x12, t2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
