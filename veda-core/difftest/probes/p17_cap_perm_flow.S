.section .text
.global _start
# R40 -- MAY AUTHORITY ITSELF MOVE THROUGH MEMORY? BOTH LAYERS NOW ASK.
#
# PERM_LOAD_CAPABILITY (bit 4) and PERM_STORE_CAPABILITY (bit 5) existed in the
# Perms word and in the specification's cause table (0x14, 0x15, both marked
# Active) and were read by NOTHING: every permBit call in the model enforced only
# EXECUTE/LOAD/STORE/ASR/SEAL/UNSEAL/INVOKE/NMC, and the only permission bits the
# RTL ever indexed were [1], [2], [3], [10], [12]. OCL.C and OCS.C -- the only
# instructions that move a CAPABILITY through memory -- were authorised by the
# plain DATA permissions.
#
# On a machine with no addresses, where every authority IS a capability, that is
# the difference between "you may read these bytes" and "you may pick up the
# authority stored in them". CAndPerm cleared the bits faithfully and CGetPerm
# reported them cleared faithfully; nothing governed anything.
#
#   w0  the owner holds all four: 0x003C
#   w1  CONTROL -- the owner spills a capability naming the secret and reads it
#       back: tag 1. Without this the probe would pass just as happily if OCS.C
#       had silently stored nothing at all.
#   w2  and it really names object 781
#   w3  the delegate, attenuated to DATA ONLY with CAndPerm: 0x002C -- bit 4 gone,
#       bit 2 kept
#   w4  THE ESCAPE IS REFUSED: mtval (c2 << 5) | 0x14 = 0x54. cap_idx is the
#       DEREFERENCED capability c2, not the destination.
#   w5  and nothing was lifted -- the destination stays untagged, 0
#   w6  the store side too: STORE without STORE_CAPABILITY -> (c5 << 5) | 0x15 = 0xB5
#   w7  traps: exactly 2
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x6, 0

    li   x1, 780
    li   x2, 0x800116000040003C            # container: Load|Store|LoadCap|StoreCap
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 781
    li   x2, 0x800117000040000C            # the SECRET object
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 780
    .insn i 0x0b, 0x5, x0, x1, 0           # bind c0 -> container
    li   x1, 781
    .insn i 0x0b, 0x5, x1, x1, 0           # bind c1 -> secret
    .insn r 0x5b, 0x0, 0x02, x3, x0, x0    # cgetperm c0
    sd   x3, 0(x31)                        # w0

    .insn r 0x0b, 0x4, 0x01, x1, x0, x6    # ocs.c  mem=c0, src=c1
    .insn r 0x0b, 0x4, 0x00, x4, x0, x6    # ocl.c  c4 <- [c0]
    .insn r 0x5b, 0x0, 0x03, x3, x4, x0    # cgettag c4
    sd   x3, 8(x31)                        # w1 -- CONTROL: 1
    .insn r 0x5b, 0x0, 0x07, x3, x4, x0    # cgetobjectid c4
    sd   x3, 16(x31)                       # w2 -- 781

    li   x7, 0xFFEF
    .insn r 0x5b, 0x1, 0x17, x2, x0, x7    # candperm c2 = c0 & ~LOAD_CAPABILITY
    .insn r 0x5b, 0x0, 0x02, x3, x2, x0
    sd   x3, 24(x31)                       # w3 -- 0x002C

    .insn r 0x0b, 0x4, 0x00, x3, x2, x6    # ocl.c c3 <- [c2] -- THE ESCAPE ATTEMPT
    sd   x28, 32(x31)                      # w4 -- 0x54
    .insn r 0x5b, 0x0, 0x03, x9, x3, x0    # cgettag c3
    sd   x9, 40(x31)                       # w5 -- 0

    li   x7, 0xFFDF
    .insn r 0x5b, 0x1, 0x17, x5, x0, x7    # candperm c5 = c0 & ~STORE_CAPABILITY
    .insn r 0x0b, 0x4, 0x01, x1, x5, x6    # ocs.c mem=c5 -- refused
    sd   x28, 48(x31)                      # w6 -- 0xB5
    sd   x29, 56(x31)                      # w7 -- 2

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mtval
    csrr x27, mepc
    addi x27, x27, 4
    csrw mepc, x27
    mret
.section .data
.align 3
.global tohost
tohost: .dword 0
.global fromhost
fromhost: .dword 0
.section .signature, "aw", @progbits
.align 8
.global begin_signature
begin_signature:
    .fill 16, 8, 0
.global end_signature
end_signature:
