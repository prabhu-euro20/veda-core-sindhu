.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_08 invariant (i) -- GLOBAL UNIQUENESS. The 44-bit Object_ID splits
# {region:20, local:24}. This proves that the SAME local index in TWO
# different regions names TWO different objects -- i.e. the region genuinely
# disambiguates and the segmentation preserves the single-address-space
# pillar (a full Object_ID means one specific object system-wide).
#
# Object_ID = 1              -> region 0, local 1  (seed Base 0x80010000, unowned)
# Object_ID = (1<<24)|1      -> region 1, local 1  (seed Base 0x80020000)
# Region 0 is the current domain (CRBR fast path); region 1 is a second
# RESIDENT domain reached through the Region Table. Same local (1), different
# region, so they MUST resolve to different objects with different Bases.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    li   x2, 1
    .insn i 0x0b, 0x5, x0, x2, 0         # veda.bind c0, x2  (region 0, local 1)
    li   x3, 16777217                    # (1 << 24) | 1
    .insn i 0x0b, 0x5, x1, x3, 0         # veda.bind c1, x3  (region 1, local 1)

    .insn r 0x5b, 0x0, 0x00, x10, x0, x0 # cgetbase x10, c0
    .insn r 0x5b, 0x0, 0x00, x11, x1, x0 # cgetbase x11, c1

    # Each must resolve to its OWN object's Base -- not just "different", the
    # exact right one, proving the region routed the lookup correctly.
    li   x20, 0x80010000
    bne  x10, x20, fail                  # region-0 local-1 Base
    li   x21, 0x80020000
    bne  x11, x21, fail                  # region-1 local-1 Base
    beq  x10, x11, fail                  # and they are genuinely distinct

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    # No access here should trap; both regions are resident.
    RVMODEL_HALT_FAIL
