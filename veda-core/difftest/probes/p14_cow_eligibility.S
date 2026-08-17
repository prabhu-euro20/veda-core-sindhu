.section .text
.global _start
# R38 -- WHO IS ENTITLED TO CAUSE A COPY-ON-WRITE SPLIT? NOW THE HARDWARE ASKS.
#
# This probe measured the defect first. The predicate used to be the whole of
#     Sail: else if need_store & entry.cow then Err(COW_FAULT)
#     RTL:  $veda_cow_write = $veda_check_odt_cow
# with the permission arm above it gated on `& not(entry.cow)`, so a principal
# holding a READ-ONLY view of a cow object took 0x0C on every store, unlimited.
#
# 0x0C IS NOT A REFUSAL. It is a REPAIR REQUEST: it instructs a handler to
# allocate, copy, and hand back a fresh WRITABLE object. Giving that to a
# principal that was never granted write is not resource waste -- it is the
# amplification the rest of the dereference chain exists to prevent, available on
# every store, forever.
#
# THE PREDICATE IS PERM_STORE, AND NO NEW PERMISSION BIT WAS NEEDED. Deleting the
# `not(entry.cow)` conjunct lets the capability's own store permission decide.
# veda.odt.set.cow deliberately does not bump the generation, so the capabilities
# that still carry store are exactly those minted BEFORE the object became
# copy-on-write. The rule the hardware now enforces:
#
#     WHOEVER HELD WRITE AUTHORITY WHEN THE OBJECT BECAME COPY-ON-WRITE MAY
#     CAUSE THE SPLIT. WHOEVER LEARNS THE NAME AFTERWARDS MAY READ.
#
# AND IT IS NOT ADVISORY. Two earlier designs put the predicate in a bit the
# delegator clears with CAndPerm; both are refuted by this codebase's own
# correction at veda_bind_insts.sail:303-307 -- "a capability handed out with
# store stripped is only ADVISORY, because the holder can re-Bind the name and
# get a fresh, fully-permissioned one". Bind's domain gate defaults to
# VEDA_DOMAIN_ANY, so anyone may re-Bind and re-derive from the entry. The
# bind-time 0xFFF7 mask is the one attenuation a re-Bind cannot escape, and this
# change is what finally gives that mask something to enforce: until now the cow
# arm caught every write regardless of Perms, so the mask's only observable
# effect was the value CGetPerm returned.
#
#   w0  the delegate binds AFTER set.cow, so it has no store permission -- 0x0004
#   w1  and a store through it is REFUSED: (c1<<5)|0x13 = 0x33, was 0x2C
#   w2  deterministically, not once: still 0x33
#   w3  THE POSITIVE CONTROL, and the probe is worthless without it. A capability
#       bound BEFORE set.cow still carries store, so copy-on-write still FIRES for
#       the party actually entitled to it: (c3<<5)|0x0C = 0x6C. Without this word
#       the probe would pass just as happily if the cow arm had been deleted.
#   w4  the ordinary control: a NON-cow object with no store permission -- 0x53
#   w5  traps: exactly 4
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    # ---- object 97: bound BEFORE it becomes cow, so c3 keeps PERM_STORE
    li   x1, 97
    li   x2, 0x800110000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 97
    .insn i 0x0b, 0x5, x3, x1, 0          # bind c3, 97 -- full Load|Store
    li   x1, 97
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2   # veda.odt.set.cow 97 <- 1  (c3 predates this)

    # ---- object 95: marked cow FIRST, so anyone binding it after is read-only
    li   x1, 95
    li   x2, 0x80010E000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 95
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2   # veda.odt.set.cow 95 <- 1

    li   x1, 95
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1, 95 -- Bind strips PERM_STORE because cow
    .insn r 0x5b, 0x0, 0x02, x3, x1, x0   # cgetperm c1
    sd   x3, 0(x31)                        # w0: 0x0004 -- LOAD only, no STORE

    li   x3, 0
    li   x4, 0xAAAA
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3   # ocs.d through the read-only delegate
    sd   x28, 8(x31)                       # w1: 0x33 -- PERM_STORE, not a repair request
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3
    sd   x28, 16(x31)                      # w2: 0x33 again -- the refusal is stable

    # ---- POSITIVE CONTROL: the pre-cow holder still gets its copy
    .insn r 0x0b, 0x3, 0x01, x4, x3, x3   # ocs.d through c3 -- must be COW, 0x6C
    sd   x28, 24(x31)                      # w3

    # ---- ORDINARY CONTROL: no store permission, no cow -- the plain refusal
    li   x1, 96
    li   x2, 0x80010F0000400004            # Perms = LOAD only, cow NOT set
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 96
    .insn i 0x0b, 0x5, x2, x1, 0          # bind c2, 96
    .insn r 0x0b, 0x3, 0x01, x4, x2, x3   # ocs.d -- PERM_STORE fault
    sd   x28, 32(x31)                      # w4: 0x53
    sd   x29, 40(x31)                      # w5: traps -- 4

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
