.include "veda_selfcheck_macros.S"
.section .text
.global _start
# D5 (DESIGN_07 Tier G) -- the CRBR saved shadow is released by NO exit other
# than xret, and it is installed by ANY later xret.
#
# Three facts, each read at source:
#   veda_crbr_save_and_reset   captures only when current_region != 0
#   veda_trap_frame_abandon    releases depth, mepcc and poison -- and never
#                              the CRBR shadow
#   veda_crbr_restore_on_xret  is called OUTSIDE the depth guard and fires on
#                              the sentinel ALONE: no depth term, no owner term
#
# So a handler entered from region 1 that leaves by a compartment crossing
# instead of mret strands saved_region = 1, and the NEXT mret -- taken by
# unrelated region-0 code, for an unrelated reason -- installs region 1 as the
# current region. This test walks exactly that path and reads the two CSRs
# that make it observable: 0x7C6 veda_current_region, 0x7C7 veda_saved_region.
#
# Object_IDs: region-1 CODE/DATA = (1<<24)|20 / |21, authority = 40,
# region-0 return pad CODE/DATA = 41 / 42.
.equ R1_CODE, (1 << 24) | 20
.equ R1_DATA, (1 << 24) | 21
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   s1, 0                              # trap counter

    csrr x5, 0x7C6
    bnez x5, fail                           # CONTROL: we start in region 0
    csrr x5, 0x7C7
    li   t4, 0xFFFFF
    bne  x5, t4, fail                       # CONTROL: the shadow starts empty

    # -- region-1 compartment: CODE (Execute|Invoke) and DATA (Invoke-only)
    la   t0, compartment_1
    slli t0, t0, 32
    li   t1, 0x02000402
    or   t0, t0, t1
    li   x1, R1_CODE
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, R1_DATA
    li   x2, 0x8002000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 40                             # type authority, Seal|Unseal
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- the region-0 return pad, built BEFORE the crossing so the handler can
    #    leave through it without minting anything itself.
    li   t1, 0xFFFFFFFFFF
    slli t1, t1, 16
    ori  t1, t1, 0x0402
    csrw 0x7C4, t1                          # veda_attr: unbounded, Execute|Invoke
    la   t2, return_pad
    li   x1, 41
    .insn r 0x0b, 0x0, 0x04, x5, x1, t2     # populate.fast

    li   x1, R1_CODE
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, R1_DATA
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, 40
    .insn i 0x0b, 0x5, x2, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2     # sealed region-1 CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2     # sealed region-1 DATA
    li   x1, 41
    .insn i 0x0b, 0x5, x5, x1, 0
    .insn r 0x5b, 0x1, 0x15, x8, x5, x0     # csealentry c8, c5 -- the return SENTRY

    # R50 increment 2: this file predates the crossing's retain mask and
    # measures a different mechanism, so it declares RETAIN ALL. The burden
    # of proving the clear works sits on vc_r50i2_crossing_clear.S, which
    # carries tight masks and the control that discriminates.
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4     # ocinvoke -> region 1
    j    fail
.balign 4
compartment_1:
    csrr x6, 0x7C6
    li   t4, 1
    bne  x6, t4, fail                       # CONTROL: inside, region is 1
    ecall                                   # trap 1: shadow captures region 1
    j    fail                               # the handler must NOT mret back here
.balign 4
return_pad:
    # We are here because the handler left by a compartment crossing, not by
    # mret. The trap frame was abandoned. Is the shadow still holding region 1?
    csrr s2, 0x7C6                          # the pad is region 0
    bnez s2, fail
    csrr s3, 0x7C7                          # THE MEASUREMENT
    li   t4, 0xFFFFF
    bne  s3, t4, fail                       # the shadow must be RELEASED here.
                                            # Before the fix this read 1 -- the
                                            # trap frame was abandoned and the
                                            # shadow was not.

    # An ordinary, unrelated region-0 trap returned by an ordinary mret. It
    # captures nothing (the capture guard is current_region != 0), so it can
    # only install what someone else left behind.
    li   s1, 1
    ecall
after_mret:
    csrr s4, 0x7C6                          # THE CONSEQUENCE
    bnez s4, fail                           # must still be region 0. Before the
                                            # fix this read 1: unrelated code
                                            # resumed inside a compartment's
                                            # region, and veda_region_is_resident
                                            # exempts the current region, which
                                            # is what R55 put an rt_valid check
                                            # on the bind path to stop.
    csrr s5, 0x7C7
    li   t4, 0xFFFFF
    bne  s5, t4, fail                       # and the shadow stays empty
    RVMODEL_HALT_PASS
.balign 4
trap_handler:
    li   t4, 1
    beq  s1, t4, second_trap
    # trap 1, from region 1: leave by a CROSSING, never touching mret.
    csrr x20, 0x7C6
    bnez x20, fail                          # CONTROL: handler runs in region 0
    csrr x21, 0x7C7
    li   t4, 1
    bne  x21, t4, fail                      # CONTROL: the shadow did capture
    li   x31, 0xFFFF
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x8, x0     # ocreturn c8 -- the architecture's
                                            # SECOND exit from a handler, and
                                            # the only one the shipped switcher
                                            # takes
    j    fail
second_trap:
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
