.section .text
.global _start
# A-3 -- veda.bind MODE 0b11 IS NOT UNCONDITIONALLY FAIL-CLOSED ON SAIL.
#
# Both layers agree that bind mode 0b11 (VEDA_BIND_RESERVED) must trap. They
# disagree about WHY, and the difference is a function of ODT and region state
# the instruction was never entitled to consult.
#
#   Sail : veda_bind_insts.sail reaches VEDA_BIND_RESERVED => Illegal_Instruction()
#          at :289 only AFTER three state-dependent traps have had their chance --
#            :211  region not resident      -> VEDA_CAUSE_REGION_FAULT     0x09
#            :284  owner_domain mismatch    -> VEDA_CAUSE_DOMAIN_VIOLATION 0x0B
#            :285  valid but not resident   -> VEDA_CAUSE_RESIDENCY_FAULT  0x0A
#   RTL  : mode 0b11 is absent from $veda_decoded (:4833-4835), so it becomes
#          $veda_undef_encoding and is refused AT DECODE -- mcause 0x02. The three
#          fault signals are gated on the three real modes only (:2346, :2379), so
#          mode 0b11 never reaches them.
#
# WHY IT MATTERS BEYOND PARITY: on Sail the refusal CAUSE for an unallocated
# encoding is a function of another domain's paging state. That is a small ODT
# oracle -- unprivileged code can issue reserved-mode binds and learn, from the
# cause alone, whether a region is resident or whether a domain matches, about
# objects it has no right to.
#
# THE EXISTING PROBE IS BLIND TWICE OVER. p5_reserved.S:26-29 uses Object_ID 1 --
# region 0, resident, owner_domain ANY -- so all three Sail gates pass and it
# measures the ONE case where the layers agree. And its handler (:48-50) counts
# traps and reads mepc; it never reads mcause. It has reported AGREE throughout.
#
#   w0  mcause of a reserved-mode bind against a NON-RESIDENT region
#       Sail 0x18 (a Veda trap) vs RTL 0x02 (illegal instruction)
#   w1  its mtval -- Sail carries cause 0x09 REGION_FAULT; RTL carries the raw
#       instruction word, which is what R33's illegal-instruction path stores
#   w2  CONTROL: the same encoding against Object_ID 1, region 0, resident --
#       the case p5 already covers, where both layers say 0x02. Without this the
#       probe could not tell a real divergence from a broken bind decode.
#   w3  traps -- 2 on both
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0
    li   x28, 0
    li   x27, 0

    # region 2 is seeded valid-but-NOT-resident on both layers
    #   Sail veda_regs.sail:1122-1123 seed regions 0 and 1 resident; 2 is not among them
    #   RTL  veda_core.tlv:291  rt_valid[2] = 1'b1; rt_resident[2] = 1'b0
    li   x1, 0x02000007
    .insn i 0x0b, 0x5, x2, x1, 3           # veda.bind mode 0b11, region 2
    sd   x28, 0(x31)                       # w0 -- mcause
    sd   x27, 8(x31)                       # w1 -- mtval

    # CONTROL: the encoding p5_reserved already exercises, region 0, resident
    li   x1, 1
    .insn i 0x0b, 0x5, x3, x1, 3           # veda.bind mode 0b11, region 0
    sd   x28, 16(x31)                      # w2 -- mcause, 0x02 expected on both
    sd   x29, 24(x31)                      # w3 -- traps, 2

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mcause
    csrr x27, mtval
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
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
