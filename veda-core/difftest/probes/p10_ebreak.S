.section .text
.global _start
# R33d -- EBREAK. Part of RV64I alongside ECALL, absent from this RTL.
#
# It is a class-B debt, not a decode hole, and the difference decides the whole
# fix: EBREAK is ALLOCATED. Sail extensions/I/base_insts.sail executes
# trap(make_sync_exception(E_Breakpoint(Brk_Software), PC)), which is mcause 3
# (core/types.sail: E_Breakpoint(Brk_Software) <-> 0b000011), NOT mcause 2. A
# decode catch-all would give it 2 with mtval = the instruction word, which is a
# confidently wrong answer rather than a fix. That is why this lands before the
# catch-all rather than inside it.
#
# mtval is policy-controlled -- xtval_exception_value() keys the breakpoint case
# on software_breakpoint_writes_xtval -- so this probe MEASURES it rather than
# assuming. The RTL must copy whatever Sail does under this project's own config.
#
#   w0  trap count after ebreak
#   w2  mcause   -- expect 3 on Sail
#   w4  mtval    -- whatever the policy says; the RTL must match it
#   w6  CONTROL: ecall still gives its own cause (0x0B), so the new arm did not
#       capture the existing one.
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x31, 0x80070000
    li   x29, 0

    ebreak
    sd   x29, 0(x31)
    sd   x27, 8(x31)
    sd   x26, 16(x31)

    ecall
    sd   x27, 24(x31)

    li   x5, 1
    la   x6, tohost
    sd   x5, 0(x6)
1:  j 1b
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x27, mcause
    csrr x26, mtval
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
