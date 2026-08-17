.section .text
.global _start
# R34 -- THE BOOT CONTEXT HAS AMBIENT AUTHORITY, AND EVERY OBJECT POLICY IS
# BYPASSABLE FROM IT.
#
# $veda_purecap_violation = ($is_load || $is_store) &&
#                           ($veda_mode[0] || ($veda_pcc_length != UNBOUNDED))
# At reset veda_mode = 0 and pcc_length = UNBOUNDED, so BOTH disjuncts are false
# and an ordinary load/store is not checked at all. It does not go through the
# capability path, so nothing the ODT says about the object is consulted.
#
# THE SCOPE IS NARROWER THAN "ANYWHERE", AND THAT MATTERS. The second disjunct
# means a compartment -- any context with a bounded PCC -- already refuses
# ordinary memory access regardless of the mode bit. So this is not a general
# hole; it is precisely the UNBOUNDED BOOT CONTEXT, which is the one context
# whose authority nothing derived.
#
# The probe measures each object policy separately rather than asserting they
# all fall together, because "copy-on-write is bypassable" is only one of them:
#   w0  cow      -- a COW object written by ordinary sd; the COW fault never fires
#   w2  bounds   -- a write past Length lands
#   w4  perms    -- a write to a load-only object lands
#   w6  tag      -- the capability tag in the granule is destroyed, silently
#   w8  traps    -- zero, for all four
#   w10 CONTROL  -- the SAME writes through the capability path DO trap, so this
#                  is the ambient path being unchecked, not the object being open
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    # object 80: Base 0x80010A00, Length 0x40, Perms = LOAD only (no store)
    li   x1, 80
    li   x2, 0x80010A0000400004
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # populate 80
    li   x1, 80
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2   # veda.odt.set.cow 80 <- 1

    li   x6, 0x80010A00

    # ---- ambient write to a COW + load-only + bounded object ----
    li   x7, 0xC0FFEE
    sd   x7, 0(x6)                         # ordinary store: no cow, no perm, no bounds
    ld   x8, 0(x6)
    sd   x8, 0(x31)                        # landed -> 0xC0FFEE
    sd   x29, 8(x31)                        # traps so far: 0

    # ---- past the object's Length (0x40) ----
    li   x7, 0xBEEF
    sd   x7, 0x40(x6)                      # one byte past the end
    ld   x9, 0x40(x6)
    sd   x9, 16(x31)                        # landed -> 0xBEEF

    # ---- and it destroys a capability tag in passing ----
    li   x1, 81
    li   x2, 0x80010B000040103C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # populate 81, full perms
    li   x1, 81
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1, 81
    li   x3, 0
    .insn r 0x0b, 0x4, 0x01, x1, x1, x3   # ocs.c -- a real tagged capability
    li   x10, 0x80010B00
    sd   x0, 0(x10)                        # ordinary store over it
    .insn r 0x0b, 0x4, 0x00, x2, x1, x3   # ocl.c it back
    .insn r 0x5b, 0x0, 0x03, x11, x2, x0  # cgettag
    sd   x11, 24(x31)                       # 0 -- the tag is gone
    sd   x29, 32(x31)                       # traps: still 0

    # ---- CONTROL: the same write THROUGH the capability path must trap ----
    li   x1, 80
    .insn i 0x0b, 0x5, x4, x1, 0          # bind c4, 80
    li   x3, 0
    li   x7, 0xDEAD
    .insn r 0x0b, 0x3, 0x01, x7, x4, x3   # ocs.d through c4 -- cow/perm must refuse
    sd   x29, 40(x31)                       # 1 -- the object's policy IS enforced there

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mepc
    addi x28, x28, 4
    csrw mepc, x28
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
    .fill 8, 8, 0
.global end_signature
end_signature:
