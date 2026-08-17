.section .text
.global _start
# R38 -- WHO IS ENTITLED TO CAUSE A COPY-ON-WRITE SPLIT? NOBODY ASKS.
#
# R19 was DECIDED: the copy is self-service, because veda_bind_perms clears bit 3
# (PERM_STORE) and leaves bit 2 (PERM_LOAD), so the principal that takes the 0x0C
# fault already holds read on the object it needs copied. Options (a), (b) and
# (c) were payments to avoid granting an authority the right party already holds.
#
# That decision left exactly ONE thing ratified as hardware and unbuilt: the
# fault's own ELIGIBILITY PREDICATE -- who is entitled to cause a split. Today
# the predicate is the whole of it:
#     Sail: else if need_store & entry.cow then Err(COW_FAULT)
#     RTL:  $veda_cow_write = $veda_check_odt_cow
# No owner test, no domain test, no permission test. The fault fires for anyone
# holding any capability to a cow entry who attempts any store.
#
# THE CONSEQUENCE IS RESOURCE, NOT CONFIDENTIALITY, and the model's own comment
# beside the fault says so: "the rest is ordering hygiene and resource
# containment". A principal handed a READ-ONLY view of a cow object can force an
# allocation on every store attempt, indefinitely, holding no write authority at
# all. Fork needs SOME principal to be able to split; nothing says which.
#
#   w0  the delegate's capability has NO store permission -- 0x000C & ~0x0008
#   w2  yet a store through it takes the COW fault
#   w4  and again -- the fault is not one-shot, so the arming repeats
#   w6  and again
#   w8  CONTROL: the same store through a NON-cow object with no store permission
#       gives 0x13 PERM_STORE, not 0x0C. So the machine CAN distinguish "you may
#       not write" from "you may not write yet" -- it just does not ask who you
#       are before choosing the second one.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    # object 95: Load|Store, then marked copy-on-write
    li   x1, 95
    li   x2, 0x80010E000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 95
    li   x2, 1
    .insn r 0x0b, 0x1, 0x07, x5, x1, x2   # veda.odt.set.cow 95 <- 1

    li   x1, 95
    .insn i 0x0b, 0x5, x1, x1, 0          # bind c1, 95 -- Bind strips PERM_STORE because cow
    .insn r 0x5b, 0x0, 0x02, x3, x1, x0   # cgetperm c1
    sd   x3, 0(x31)                        # 0x0004: LOAD only, no STORE

    li   x3, 0
    li   x4, 0xAAAA
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3   # ocs.d -- COW fault
    sd   x28, 8(x31)                       # mtval: cause 0x0C
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3
    sd   x28, 16(x31)                      # again
    .insn r 0x0b, 0x3, 0x01, x4, x1, x3
    sd   x28, 24(x31)                      # and again -- nothing rate-limits or refuses

    # CONTROL: a NON-cow object with store permission removed gives 0x13, not 0x0C
    li   x1, 96
    li   x2, 0x80010F0000400004            # Perms = LOAD only, cow NOT set
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 96
    .insn i 0x0b, 0x5, x2, x1, 0          # bind c2, 96
    .insn r 0x0b, 0x3, 0x01, x4, x2, x3   # ocs.d -- PERM_STORE fault
    sd   x28, 32(x31)                      # cause 0x13, not 0x0C
    sd   x29, 40(x31)                      # traps: 4

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
