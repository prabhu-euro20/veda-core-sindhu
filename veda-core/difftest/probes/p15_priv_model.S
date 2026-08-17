.section .text
.global _start
# R36/R39 -- THE PRIVILEGE MODEL, MEASURED ACROSS BOTH LAYERS.
#
# THIS PROBE COULD NOT HAVE BEEN WRITTEN BEFORE THIS INCREMENT, and p13's own
# header says so in as many words: OSpecialRW was "a clean cross-layer
# measurement, UNLIKE THE PRIVILEGE MODEL, because OSpecialRW exists on both
# layers". It did not exist for privilege, because the two layers did not share
# a mechanism for leaving Machine mode:
#
#     Sail : mstatus.MPP + mret, standard, already implemented
#     RTL  : veda.droppriv, Custom-3, one-way, with no trap arm and no mret arm,
#            and defined in the model ZERO times
#
# R36 recorded that and deliberately did not fix it, because the two candidate
# answers were opposite. The answer turned out to be forced rather than chosen:
# Milestone 4's addendum justified the custom instruction on the ground that
# "real mret is a trap-return semantic this core has no trap to return from",
# and Milestone 9 built the traps and MRET. The premise expired; the instruction
# outlived it. So the RTL moved to the model and nothing had to be specified.
#
#   w0  mstatus.MPP after the architected clear -- 0 (User) on both. If this
#       diverges, nothing below means anything.
#   w1  a Machine-only CSR READ from User -- must leave 0xBAD standing. The RTL
#       had NO generic privilege check at all (no csr_addr[9:8] test anywhere),
#       so all fourteen of its CSRs were readable and writable from User --
#       mtvec included, which is the trap vector itself.
#   w2  ...and the cause is 0x02 Illegal_Instruction, from check_CSR_priv, which
#       runs ABOVE every Veda write_CSR clause. The RTL's own R27 test used to
#       assert a trap count of ZERO here and call it Sail parity.
#   w3  trap count so far: 1
#   w4  MRET from User is itself illegal -- cause 0x02, and control resumes AFTER
#       it rather than at mepc. Without this gate the whole increment inverts:
#       unprivileged code would write mstatus.MPP and mret itself into Machine.
#   w5  trap count: 2
#   w6  ecall from User -- 0x08 E_U_EnvCall. The RTL hardcoded 0x0B, "from
#       Machine mode", for every ecall regardless of privilege, with the comment
#       "the only possible value since this core only ever runs M-mode" -- false
#       in the same file, which defined $priv and had ten tests that cleared it.
#       A compartment's syscall announced itself to the handler as the kernel's.
#   w7  trap count: 3
#   w8  CONTROL: ordinary unprivileged arithmetic still runs. A layer that simply
#       trapped everything after the drop would otherwise pass this whole probe.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0                            # trap count
    li   x27, 0                            # cause of the most recent trap

    li   x1, 0x1800                        # mstatus.MPP, bits 12:11
    csrc mstatus, x1
    csrr x2, mstatus
    srli x2, x2, 11
    andi x2, x2, 3
    sd   x2, 0(x31)                        # w0

    la   x3, umode
    csrw mepc, x3
    mret

umode:
    li   x4, 0xBAD
    csrr x4, 0x7c1                         # Machine-only CSR, read, from User
    sd   x4, 8(x31)                        # w1
    sd   x27, 16(x31)                      # w2
    sd   x29, 24(x31)                      # w3

    mret                                   # illegal below Machine
    sd   x27, 32(x31)                      # w4
    sd   x29, 40(x31)                      # w5

    ecall
    sd   x27, 48(x31)                      # w6
    sd   x29, 56(x31)                      # w7

    li   x5, 7
    addi x5, x5, 3
    sd   x5, 64(x31)                       # w8 CONTROL -- 10 on both

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x27, mcause
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
    .fill 16, 8, 0
.global end_signature
end_signature:
