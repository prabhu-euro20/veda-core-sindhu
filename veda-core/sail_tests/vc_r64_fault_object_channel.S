.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R64 -- the bind-side fault-identification channel, CSR 0x7C9 veda_mfaultobj.
#
# DESIGN_02:293-297 names this gap in its own words and says where it belongs in
# the order of work:
#   "The handler cannot identify which object faulted. mtval carries
#    {cap_idx, cause}, not an Object_ID ... That is a software workaround for a
#    missing architectural channel, and it should be resolved BEFORE `backing`
#    is designed rather than after."
#
# CGetObjectID closed it for the COPY-ON-WRITE fault, where a live capability
# exists to interrogate. It does NOT close it on the BIND side: the residency
# trap passes `rd`, the destination register of a Bind that never completed, so
# no capability names the faulting object and nothing can recover it.
#
# FAIL-CLOSED BY CONSTRUCTION. veda_trap has fifty-three call sites and is left
# untouched; a second entry point veda_trap_obj carries the name, and the single
# trap chokepoint writes VEDA_OBJECT_NONE whenever nothing was staged. An
# unconverted site can only cost information -- no edit makes this register
# report the WRONG object.
#
# EVERY REGISTER BELOW IS NAMED BY NUMBER, DELIBERATELY. The first draft wrote
# `li s11, ...` for the sentinel and `li t3, ...` for a compare while using x27
# and x28 as the trap counter and a result -- s11 IS x27 and t3 IS x28. That is
# the third ABI-alias collision this register has recorded (R62 was `t4` versus
# `x29`), and every one of them turned a check into a comparison of a value with
# itself.
#
#   x27 trap counter   x26 last mtval    x25 VEDA_OBJECT_NONE
#   x18..x23 results   x17 handler temp  x1..x10, x30 scratch
.equ OBJ_MISSING, 400
.equ OBJ_PAGED,   401
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x25, 0xFFFFFFFFFFF                 # VEDA_OBJECT_NONE

    # CONTROL 1: the channel resets to the SENTINEL, not to zero. Object 0 is a
    # legal name, so a zero reset makes "nothing faulted" and "object 0 faulted"
    # the same reading -- R10's argument for the CRBR's out-of-window sentinel.
    # The first version of this register did reset to zero and this line caught it.
    csrr x18, 0x7C9
    bne  x18, x25, fail

    # THE CHANNEL, case 1: a name that was never populated.
    li   x1, OBJ_MISSING
    .insn i 0x0b, 0x5, x3, x1, 0            # veda.bind c3, 400
    li   x8, 1
    bne  x27, x8, fail
    andi x8, x26, 0x1f
    li   x9, 0x05
    bne  x8, x9, fail                       # OBJECT_NOT_FOUND
    csrr x19, 0x7C9
    li   x9, OBJ_MISSING
    bne  x19, x9, fail                      # the handler now knows WHICH

    # FAIL-CLOSED, first demonstration: an ordinary trap that consulted no
    # descriptor must clear the channel. Without this a stale name survives into
    # an unrelated trap and a pager acts on somebody else's object -- the same
    # shape as R60's stale CRBR shadow.
    ecall
    li   x8, 2
    bne  x27, x8, fail
    csrr x20, 0x7C9
    bne  x20, x25, fail
    li   x21, 0x600D

    # THE CHANNEL, case 2: the case DESIGN_02 actually asks for. A residency
    # fault mints nothing, so no capability exists to interrogate.
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, OBJ_PAGED
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     # populate 401
    li   x8, 2
    bne  x27, x8, fail
    li   x1, OBJ_PAGED
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0     # page.out 401
    li   x8, 2
    bne  x27, x8, fail
    li   x1, OBJ_PAGED
    .insn i 0x0b, 0x5, x4, x1, 0            # veda.bind c4, 401 -- residency fault
    li   x8, 3
    bne  x27, x8, fail
    andi x8, x26, 0x1f
    li   x9, 0x0A
    bne  x8, x9, fail                       # RESIDENCY_FAULT
    csrr x22, 0x7C9
    li   x9, OBJ_PAGED
    bne  x22, x9, fail                      # and THIS is what a pager needs
    .insn r 0x5b, 0x0, 0x03, x10, x4, x0    # cgettag -- nothing was minted,
    bnez x10, fail                          # which is why nothing else can name it

    # CONTROL 2: the channel is READ-ONLY, and its refusal is itself fail-closed.
    # An illegal CSR write stages no name, so the chokepoint writes the sentinel
    # -- a second, independent demonstration of the clear, this time on a trap
    # that is not a Veda trap at all.
    li   x1, 7
    csrw 0x7C9, x1
    li   x9, 4
    bne  x27, x9, fail                      # the write trapped
    csrr x23, 0x7C9
    bne  x23, x25, fail                     # sentinel: not 7, not the old name
    li   x24, 0x600D

    li   x9, 0x600D
    bne  x21, x9, fail
    bne  x24, x9, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
.section .data
.balign 64
arena:
    .space 64
