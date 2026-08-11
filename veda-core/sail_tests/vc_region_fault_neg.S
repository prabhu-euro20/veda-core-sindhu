.include "veda_selfcheck_macros.S"
.section .text
.global _start
# DESIGN_08 invariant (iii) -- EXPLICIT REGION FAULT (the cache-less pillar).
# Binding an object whose domain (region) is not currently resident must
# raise a bounded, EXPLICIT trap (VEDA_CAUSE_REGION_FAULT, 0x09), never
# resolve silently. A silent miss is exactly the cache-timing behaviour the
# cache-less pillar exists to eliminate; a region fault is a real,
# recoverable event -- the handler would page the domain's table in and retry.
#
# Object_ID = (2<<24)|7 -> region 2, local 7. Region 2 is seeded NON-RESIDENT
# in the Region Table (RT[2].region_resident = false), even though its object
# exists in backing. So the bind must trap with cause 0x09, cap_idx 0 (c0).
# This is DISTINCT from OBJECT_NOT_FOUND (0x05): the object exists, its table
# is just paged out.
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 33554439                    # (2 << 24) | 7, region 2 (non-resident)
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- must REGION_FAULT

    RVMODEL_HALT_FAIL                     # reached only if the bind wrongly resolved
.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18                        # E_Extension (all Veda hard traps)
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x09                        # cause=0x09 (REGION_FAULT), cap_idx=0 (c0)
    bne  t3, t4, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
