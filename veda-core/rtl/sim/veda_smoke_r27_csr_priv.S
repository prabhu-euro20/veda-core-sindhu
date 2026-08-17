#include "veda_priv_macros.h"
.section .text
.global _start
// R39 -- THE GENERIC CSR PRIVILEGE CHECK, WHICH THIS LAYER NEVER HAD.
//
// This test is the one that recorded the gap, and then asserted it was correct.
// Its own former header said so plainly: "This layer has NO standard CSR
// privilege check at all -- verified by grep, no csr_addr[9:8] test anywhere",
// and it went on to assert a trap count of ZERO for unprivileged reads AND
// writes of 0x7C0-0x7C3, calling that "matching Sail: the register holds,
// nothing traps".
//
// It does not match Sail. check_CSR() is a conjunction, and check_CSR_priv runs
// FIRST, above every Veda clause:
//     csrPriv(csr) = csr[9..8]
//     check_CSR_priv(csr, p) = privLevel_to_CSR_privbits(p) >=_u csrPriv(csr)
// User's CSR privilege bits are 0b00 and every CSR this core implements sits at
// 0x3xx or 0x7Cx, so csrPriv is 0b11 for all fourteen and the access is illegal
// before any write_CSR clause is reached. Verified by running the model rather
// than reading it: from U-mode, `csrr x10, 0x7c1` raises Illegal_Instruction
// with mepc at the csrr itself. The old test matched the INNER clause and
// missed the gate above it.
//
// WHAT WAS ACTUALLY REACHABLE, which is worse than the four CSRs R27 named.
// mtvec's only guard was $veda_csr_escape_violation, which fires only while a
// compartment is LIVE -- so unprivileged code OUTSIDE a compartment could
// install its own trap vector. mscratch, mepc, mcause and mtval had no guard
// whatsoever. This test now exercises all ten.
//
//   x10/x11/x12/x17  privileged capture, before the drop
//   x13              stays 0xBAD -- an unprivileged CSR READ never executes
//   x20              trap count, must be 11: one per refused access, plus the
//                    final ecall that gets a privileged handler to read back
//   x21              stays 0 -- the hijacked trap vector never ran
//   x22              0x600D -- the privileged read-back found every register,
//                    mtvec included, exactly as it was
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0
    li   x21, 0
    li   x22, 0

    // capture the privileged values first
    csrr x10, 0x7c1                        // pcc_length, expect FFFFFFFFFF at reset
    csrr x11, 0x7c0                        // pcc_base
    csrr x12, 0x7c3                        // mepcc_length
    csrr x17, 0x7c2                        // mepcc_base

    VEDA_DROP_TO_USER(x27, x28)            // R36: the architected drop

    // ---- the four R27 named. Each must now TRAP, not silently no-op.
    li   x6, 0x40
    csrw 0x7c1, x6                         // 1
    li   x13, 0xBAD
    csrr x13, 0x7c1                        // 2 -- reads are gated too
    li   x6, 0xBEEF
    csrw 0x7c0, x6                         // 3
    li   x6, 0x80
    csrw 0x7c3, x6                         // 4
    // 0x7C2 was added after its mutant SURVIVED: the first draft wrote three of
    // the four, so the fourth's gate was unverified. Four-of-three is the same
    // shape as the atomic/sealed omission the census caught one increment ago.
    li   x6, 0xBEEF
    csrw 0x7c2, x6                         // 5

    // ---- and the six R27 never looked at. This is the real finding.
    la   x6, evil_handler
    csrw mtvec, x6                         // 6 -- THE TRAP VECTOR
    li   x6, 0x1
    csrw mscratch, x6                      // 7
    csrw mepc, x6                          // 8
    csrw mcause, x6                        // 9
    csrw mtval, x6                         // 10

    ecall                                  // 11 -- get a privileged handler

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x14, mcause
    li   x15, 0x08                         // E_U_EnvCall: the read-back request
    beq  x14, x15, h_final
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret

h_final:
    // The handler is privileged -- that is R36 -- so it can do the read-back the
    // dropped code no longer can. Every register must be exactly as captured.
    csrr x16, 0x7c1
    bne  x16, x10, h_done
    csrr x16, 0x7c0
    bne  x16, x11, h_done
    csrr x16, 0x7c3
    bne  x16, x12, h_done
    csrr x16, 0x7c2
    bne  x16, x17, h_done
    csrr x16, mtvec
    la   x18, trap_handler
    bne  x16, x18, h_done                  // mtvec must still be OURS
    csrr x16, mscratch
    bnez x16, h_done
    li   x22, 0x600D
h_done:
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret

// If the hijack had landed, control would arrive here instead and never leave.
evil_handler:
    li   x21, 0xDEAD
2:  j 2b
