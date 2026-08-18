.include "veda_selfcheck_macros.S"
.section .text
.global _start
# THE POLICY WRITE PATH -- veda.odt.set.domain
#
# The first instruction in this design that changes an ODT entry WITHOUT
# changing what the object is. Every other writer (Populate, Populate-Fast,
# Destroy) bumps the generation, which kills every outstanding capability.
#
# PHASE 2 IS THE WHOLE POINT OF THE INSTRUCTION. Narrowing who may bind an
# object must NOT invalidate the capabilities held by those still entitled to
# it -- otherwise declaring a sharing rule destroys the sharing it describes,
# and both copy-on-write and per-object bind authority stay impossible. If this
# phase ever fails, the instruction has become an expensive Populate.
#
#   1. bind object 1, use it -- the capability works
#   2. narrow it to domain 5, then USE THE SAME CAPABILITY AGAIN. It must still
#      work, and must still read back the value stored before the narrowing:
#      the generation was not bumped and the contents were not touched
#   3. bind it again from boot. Boot is in no compartment, so it is allowed
#      regardless of policy -- that is the bootstrap and the pager
#   4. widen it back to ANY and bind again, proving the field is really being
#      read rather than the gate being dead
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0                    # trap counter

    # ---- phase 1: an ordinary bind and a round-trip
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, 1
    li   x2, 0
    li   x3, 0xBEEF
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d c0, 0, x3
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d c0, 0, x10
    li   x6, 0xBEEF
    bne  x10, x6, fail
    li   x21, 0x600D

    # ---- phase 2: narrow the object, then reuse the SAME capability
    li   x1, 1
    # R62 (D6): this read `li x4, 5` and set.domain now REFUSES it -- region 5
    # has rt_valid = false, it has never been configured, so domain 5 is not a
    # principal but a principal that DOES NOT EXIST YET. FOUR tests across the
    # two layers named such a domain and not one named a real principal, which
    # is exactly why the missing check was invisible. Region 1 is real,
    # configured and resident; nothing else about this test changes.
    li   x4, 1                     # domain 1 -- a REAL, configured region
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4   # veda.odt.set.domain
    bne  x20, x0, fail             # the write itself must not trap

    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d through the OLD c0
    li   x6, 0xBEEF
    bne  x10, x6, fail             # a bumped generation would trap 0x02 here
    bne  x20, x0, fail             # and still no trap at all
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # and it can still STORE
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2
    li   x6, 0xF00D
    bne  x10, x6, fail
    li   x22, 0x600D

    # ---- phase 3: boot is in no compartment, so it may still bind
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, 1 -- must SUCCEED
    .insn r 0x5b, 0x0, 0x03, x11, x1, x0  # cgettag x11, c1
    li   x6, 1
    bne  x11, x6, fail
    bne  x20, x0, fail
    li   x23, 0x600D

    # ---- phase 4: widen it back, proving the field is genuinely consulted
    li   x1, 1
    li   x4, 0xFFFFF               # VEDA_DOMAIN_ANY
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, 1
    .insn r 0x5b, 0x0, 0x03, x12, x2, x0
    li   x6, 1
    bne  x12, x6, fail
    bne  x20, x0, fail
    li   x24, 0x600D

    li   x6, 0x600D
    bne  x21, x6, fail
    bne  x22, x6, fail
    bne  x23, x6, fail
    bne  x24, x6, fail
    RVMODEL_HALT_PASS

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    RVMODEL_HALT_FAIL
