.section .text
.global _start
# R41 -- A POPULATE MINTS A NEW OBJECT. THE PREVIOUS OCCUPANT'S POLICY MUST NOT
# ATTACH TO IT, AND ON ONE LAYER IT DID.
#
#     VEDA_ODT_POPULATE       Sail: cow = old_entry.cow          RTL: cow <= 0
#                             Sail: owner_domain = old_entry...  RTL: <= ANY
#     VEDA_ODT_POPULATE_FAST  Sail: cow = false                  RTL: cow <= 0
#                             Sail: owner_domain = ANY           RTL: <= ANY
#
# So the two Sail populate variants disagreed with EACH OTHER on both policy
# fields, and plain Populate disagreed with the RTL on both. The RTL had the
# reasoning written down -- "Populate may reuse a slot whose previous object was
# copy-on-write -- without this, the new object would be born copy-on-write and
# its first write would fault for no reason" -- and the odt_entry struct's own
# comment on owner_domain says VEDA_DOMAIN_ANY is "how every object is created",
# which plain Populate made false.
#
# R38 IS WHAT TURNED THIS FROM A NUISANCE INTO A LOCKOUT. While the copy-on-write
# arm ignored capability permissions, a stale `cow` only meant a spurious 0x0C
# that a handler could clear. Now the split right belongs to whoever held
# PERM_STORE when the object became copy-on-write -- and an object BORN
# copy-on-write has no such principal, ever. Populate returns a status in rd, not
# a capability, so the minter must Bind, and Bind masks store off a cow entry.
# The freshly minted object would be unwritable by anyone, from creation.
#
# WHY NOTHING CAUGHT IT: no probe in this suite composed Populate with set.cow.
# A divergence in two policy fields sat in a differential harness that reported
# 16/16, because the states it diverged on were never entered.
#
#   w0  Perms of a capability bound to the RE-POPULATED object -- 0x000C. If the
#       stale cow survived the mint, Bind masks bit 3 off and this reads 0x0004.
#   w1  and a store through it SUCCEEDS -- traps still 0
#   w2  CONTROL: a genuinely copy-on-write object still refuses a post-cow
#       binder, (c2 << 5) | 0x13 = 0x53. Without this the probe would pass just
#       as happily if copy-on-write had been deleted outright.
#   w3  traps -- exactly 1
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x7, 0                             # the offset GPR, kept separate

    # ---- object 98: created, marked copy-on-write, then RE-POPULATED
    li   x1, 98
    li   x2, 0x800111000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 98
    li   x1, 98
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2    # veda.odt.set.cow 98 <- 1

    li   x1, 98
    li   x2, 0x800111000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 98 AGAIN -- a NEW object

    li   x1, 98
    .insn i 0x0b, 0x5, x1, x1, 0           # bind c1, 98 -- after the re-mint
    .insn r 0x5b, 0x0, 0x02, x3, x1, x0    # cgetperm c1
    sd   x3, 0(x31)                        # w0: 0x000C, not 0x0004

    li   x4, 0x5A5A
    .insn r 0x0b, 0x3, 0x01, x4, x1, x7    # ocs.d -- a new object must be writable
    sd   x29, 8(x31)                       # w1: traps still 0

    # ---- CONTROL: a real copy-on-write object still refuses a post-cow binder
    li   x1, 99
    li   x2, 0x800112000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    # populate 99
    li   x1, 99
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2    # veda.odt.set.cow 99 <- 1
    li   x1, 99
    .insn i 0x0b, 0x5, x2, x1, 0           # bind c2, 99 -- store masked off
    .insn r 0x0b, 0x3, 0x01, x4, x2, x7    # ocs.d -- refused
    sd   x28, 16(x31)                      # w2: 0x53
    sd   x29, 24(x31)                      # w3: traps -- 1

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
    .fill 8, 8, 0
.global end_signature
end_signature:
