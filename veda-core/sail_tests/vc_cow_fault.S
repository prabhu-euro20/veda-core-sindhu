.include "veda_selfcheck_macros.S"
.section .text
.global _start
# COPY-ON-WRITE -- DESIGN_02 Mechanism 2, and the two phases that decide
# whether it is real or advisory.
#
# PHASE 3: the capability minted BEFORE the object became copy-on-write must
# still be caught. set.cow deliberately does not bump the generation, so that
# capability is still live and still carries store permission. At fork() the
# parent is holding exactly such a capability, and it is the first one that
# will be written. A check reading the CAPABILITY would miss it; this one reads
# the ENTRY.
#
# PHASE 5: re-binding must not escape. DESIGN_02's own correction records that
# handing out a store-stripped capability is only ADVISORY, because the holder
# can re-Bind the name and receive a fresh, fully-permissioned one. The
# attenuation therefore lives in Bind itself, where the entry is the authority.
#
# The cause is 0x0C, NOT the store-permission violation 0x13, so a handler can
# tell "make a private copy" apart from "this program has a bug".
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0

    # ---- phase 1: an ordinary object, written and read back
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, 1
    li   x2, 0
    li   x3, 0xC0DE
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d
    li   x6, 0xC0DE
    bne  x10, x6, fail
    li   x21, 0x600D

    # ---- phase 2: mark it copy-on-write
    li   x1, 1
    li   x4, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 1
    bne  x20, x0, fail                    # setting policy must not trap

    # ---- phase 3: the OLD capability still stores -- and must now FAULT
    li   x3, 0xBAD
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d c0 -- must TRAP (1)
    li   x6, 1
    bne  x20, x6, fail
    li   x6, 0x0C                         # (cap_idx 0 << 5) | 0x0C
    bne  x25, x6, fail                    # COW fault, NOT 0x13
    li   x22, 0x600D

    # ---- phase 4: reads still work, which is the point of sharing
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2  # ocl.d c0 -- must SUCCEED
    li   x6, 0xC0DE
    bne  x10, x6, fail                    # and the refused store never landed
    li   x6, 1
    bne  x20, x6, fail                    # still exactly one trap
    li   x23, 0x600D

    # ---- phase 5: re-binding must NOT hand back store permission
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, 1 -- fresh capability
    .insn r 0x5b, 0x0, 0x02, x11, x1, x0  # cgetperm x11, c1
    andi x12, x11, 8                      # bit 3 = Permit_Store
    bnez x12, fail                        # a fresh bind must not restore it
    li   x24, 0x600D

    # ---- phase 6: NMC_ADD writes memory too, so it must fault as well
    li   x3, 5
    .insn r 0x0b, 0x3, 0x02, x13, x0, x3  # nmc_add.d via c0 -- must TRAP (2)
    li   x6, 2
    bne  x20, x6, fail
    li   x6, 0x0C
    bne  x25, x6, fail
    li   x26, 0x600D

    # ---- phase 7: clearing the bit restores writes, so the field is live
    li   x1, 1
    li   x4, 0
    .insn r 0x0b, 0x1, 0x07, x5, x1, x4   # veda.odt.set.cow 1 <- 0
    li   x3, 0xF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2   # ocs.d c0 -- must SUCCEED now
    li   x10, 0
    .insn r 0x0b, 0x3, 0x00, x10, x0, x2
    li   x6, 0xF00D
    bne  x10, x6, fail
    li   x6, 2
    bne  x20, x6, fail                    # still exactly two traps
    li   x27, 0x600D

    li   x6, 0x600D
    bne  x21, x6, fail
    bne  x22, x6, fail
    bne  x23, x6, fail
    bne  x24, x6, fail
    bne  x26, x6, fail
    bne  x27, x6, fail
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
