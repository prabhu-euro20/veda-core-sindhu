.include "veda_selfcheck_macros.S"
.section .text
.global _start
# R80 -- mtvec is DIRECT-ONLY, and MODE is read-only zero.
#
# RISC-V Privileged section 3.1.7, verbatim: "the CSR contains only bits XLEN-1
# through 2 of the address BASE. When used as an address, the lower two bits are
# filled with zeroes to obtain an XLEN-bit address that is always aligned on a
# 4-byte boundary." The same section permits the narrowing outright: "If mtvec is
# writable, the set of values the register may hold can vary by implementation."
# CHERIoT ISA v1.0 section 7.10 takes the same route ("Only direct mode is
# supported").
#
# WHY IT IS A SECURITY RULE HERE AND NOT HOUSEKEEPING. This core uses mtvec as a
# RAW trap target -- no MODE decode, no +4*cause. A Vectored write that both
# layers stored IDENTICALLY sent the specification into the handler and the
# implementation ONE BYTE INTO IT, permanently, because the fetch array is
# byte-granular. The trap path is the recovery path; a divergence that ends
# execution there is the worst one the machine can have.
#
# FOUR ROWS, and row 4 is the anti-vacuity control: without it a core that
# answered zero to every mtvec read would pass rows 1-3.
#
# Every register by NUMBER.
_start:
    li   x27, 0

    # ROW 1 -- Reserved MODE 0b10 via the immediate form
    csrwi mtvec, 2
    csrr x2, mtvec
    bnez x2, fail

    # ROW 2 -- Reserved MODE 0b11 ORed over a real base
    li   x3, 0x80001000
    csrw mtvec, x3
    li   x4, 3
    csrrs x0, mtvec, x4
    csrr x5, mtvec
    bne  x5, x3, fail

    # ROW 3 -- Vectored MODE 0b01. A LEGAL RISC-V mode, and the one that used to
    #          diverge silently: both layers stored it, then disagreed on where
    #          the trap went.
    li   x6, 0x80002000
    ori  x7, x6, 1
    csrw mtvec, x7
    csrr x8, mtvec
    bne  x8, x6, fail

    # ROW 4 -- CONTROL, ANTI-VACUITY. An already-aligned write must survive
    #          EXACTLY. A core that zeroed mtvec outright passes rows 1-3.
    li   x9, 0x80003000
    csrw mtvec, x9
    csrr x10, mtvec
    bne  x10, x9, fail

    # ROW 5 -- THE ONE THAT MATTERED. Install the real handler WITH MODE=0b01
    #          and take a genuine trap. Reaching `verdict` at all proves the
    #          handler was entered at the aligned base and returned.
    la   x30, trap_handler
    ori  x30, x30, 1
    csrw mtvec, x30
    li   x20, 0
    ecall
    li   x11, 0xC0DE
    bne  x20, x11, fail
    li   x12, 1
    bne  x27, x12, fail            # exactly one trap, and it was ours
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
.balign 4
trap_handler:
    addi x27, x27, 1
    li   x20, 0xC0DE
    csrr x22, mepc
    addi x22, x22, 4
    csrw mepc, x22
    mret
