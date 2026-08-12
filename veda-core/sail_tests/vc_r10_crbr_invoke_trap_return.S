.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R10 (DESIGN_07 Tier G) -- the POSITIVE round-trip: the CRBR tracks the
# domain across invoke -> trap -> mret -> return, and is directly observable
# via the new read-only CSR 0x7C6 (veda_current_region) / 0x7C7
# (veda_saved_region).
#
# Region 1 is seeded RESIDENT (RT[1].region_resident = true, base = entry
# 256), so a region-1 compartment can be legitimately built and entered.
# This proves the four behaviours the two negative tests cannot:
#   1. OCInvoke into a RESIDENT non-zero region SUCCEEDS and loads the CRBR
#      (0x7C6 becomes 1 inside the compartment; it was 0 before).
#   2. A trap taken inside that compartment RESETS the CRBR to region 0
#      (the handler runs in the root domain) and SAVES region 1 to 0x7C7.
#   3. mret RESTORES the CRBR to region 1, self-consuming (0x7C7 reads back
#      the empty sentinel 0xFFFFF afterwards).
#   4. Returning to the unbounded root via a region-0 sentry loads the CRBR
#      back to region 0.
#
# Object_IDs: region-1 CODE = (1<<24)|20, region-1 DATA = (1<<24)|21,
# type-authority (region 0) = 40, region-0 return sentry code = 41.
.equ R1_CODE, (1 << 24) | 20
.equ R1_DATA, (1 << 24) | 21
_start:
    la   t0, trap_handler
    csrw mtvec, t0

    # CRBR starts at the reset default, region 0.
    csrr x5, 0x7C6
    bnez x5, fail

    # -- Populate a region-1 CODE object. Base = compartment_1, Length 0x200,
    #    Perms Execute|Invoke = 0x0402. The Length must cover ALL the code
    #    that runs inside the compartment -- the resume-after-trap sequence
    #    and the whole return-object build below execute under this PCC
    #    bound, so 0x40 would fetch-fault partway through; 0x200 (512 B)
    #    covers it. Region 1 is resident, so populate resolves through RT[1]
    #    and lands at entry 256+20.
    la   t0, compartment_1
    slli t0, t0, 32
    li   t1, 0x02000402
    or   t0, t0, t1
    li   x1, R1_CODE
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate

    # -- region-1 DATA object: Base 0x80020000 (region-1 RAM), Invoke-only
    #    0x0400 (non-executable, satisfies OCInvoke's data check).
    li   x1, R1_DATA
    li   x2, 0x8002000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate

    # -- type-authority object (region 0), Permit_Seal|Permit_Unseal 0x0300.
    li   x1, 40
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate

    # Bind all three. The region-1 binds succeed because region 1 is
    # resident; each resolves via RT[1] (cross-region from the current
    # region 0), exercising exactly the DESIGN_08 RT-read path.
    li   x1, R1_CODE
    .insn i 0x0b, 0x5, x0, x1, 0          # veda.bind c0, x1  -- region-1 CODE
    li   x1, R1_DATA
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, x1  -- region-1 DATA
    li   x1, 40
    .insn i 0x0b, 0x5, x2, x1, 0          # veda.bind c2, x1  -- authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2  -- sealed region-1 CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2  -- sealed region-1 DATA

    # -- Enter the region-1 compartment. CRBR must load region 1.
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4

    j    fail                              # OCInvoke must jump, not fall through
.balign 4
compartment_1:
    # (1) inside region 1: the CRBR is now 1.
    csrr x6, 0x7C6                          # veda_current_region -- expect 1
    li   t4, 1
    bne  x6, t4, fail

    # (2) trap out. The handler resets CRBR to 0 and saves 1.
    ecall
compartment_1_resume:
    # (3) back inside region 1 via mret: CRBR restored to 1, saved shadow
    #     self-consumed back to the empty sentinel.
    csrr x7, 0x7C6                          # veda_current_region -- expect 1 again
    li   t4, 1
    bne  x7, t4, fail
    csrr x8, 0x7C7                          # veda_saved_region -- expect 0xFFFFF (consumed)
    li   t4, 0xFFFFF
    bne  x8, t4, fail

    # (4) return to the unbounded root. Build a region-0 unbounded return
    #     CODE object and invoke into it, widening PCC back and loading the
    #     CRBR back to region 0. Use the wide populate path for the 40-bit
    #     unbounded Length sentinel (veda_attr = Length[55:16]|Perms[15:0]).
    li   t1, 0xFFFFFFFFFF
    slli t1, t1, 16
    ori  t1, t1, 0x0402                     # Execute|Invoke
    csrw 0x7C4, t1                          # veda_attr
    la   t2, return_pad
    li   x1, 41
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2    # veda.odt.populate.fast (region 0, unbounded)
    li   x1, 42
    li   x2, 0x8001090000400400            # region-0 DATA, Invoke-only
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 41
    .insn i 0x0b, 0x5, x5, x1, 0          # bind c5, return CODE
    li   x1, 42
    .insn i 0x0b, 0x5, x6, x1, 0          # bind c6, return DATA
    li   x1, 40
    .insn i 0x0b, 0x5, x7, x1, 0          # rebind authority into c7
    .insn r 0x5b, 0x1, 0x10, x8, x5, x7   # cseal c8, c5, c7  -- sealed return CODE
    .insn r 0x5b, 0x1, 0x10, x9, x6, x7   # cseal c9, c6, c7  -- sealed return DATA
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9   # ocinvoke c8, c9  -- widen PCC, CRBR -> region 0
    j    fail
.balign 4
return_pad:
    # (4 cont.) back in the unbounded root: CRBR is region 0 again.
    csrr x10, 0x7C6                         # veda_current_region -- expect 0
    bnez x10, fail
    RVMODEL_HALT_PASS
.balign 4
trap_handler:
    # (2 cont.) the handler runs in the ROOT domain: CRBR was reset to 0,
    # and region 1 was saved to the shadow.
    csrr x20, 0x7C6                         # veda_current_region -- expect 0 in-handler
    bnez x20, fail
    csrr x21, 0x7C7                         # veda_saved_region -- expect 1
    li   t4, 1
    bne  x21, t4, fail
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
