.section .text
.global _start
// R27 -- the four compartment-state CSRs that rewrite PCC and MEPCC had NO
// privilege gate, while 0x7C5 (which merely toggles purecap) had one. The
// weaker gate was on the stronger authority.
//
// This layer has NO standard CSR privilege check at all -- verified by grep, no
// csr_addr[9:8] test anywhere -- so before R27 the ONLY thing standing between
// unprivileged code and its own execution bounds was $veda_csr_escape_violation,
// which tests veda_pcc_length against VEDA_PCC_UNBOUNDED. R26 records that that
// predicate is forgeable. So on hardware these CSRs were reachable by any
// unprivileged code that had forged the predicate.
//
// veda.droppriv is one-way: $priv can never be set again short of reset
// (veda_core.tlv:1020). So this test drops once and everything after is
// unprivileged.
//
// P1  write 0x7C1 (veda_pcc_length) unprivileged -> must be a SILENT NO-OP,
//     matching Sail: the register holds, nothing traps, read-back is unchanged.
// P2  same for 0x7C0 (veda_pcc_base).
// P3  same for 0x7C3 (veda_mepcc_length) -- the trap-return forge.
// P4  control: the reads themselves still work, and no trap fired at all, so
//     P1-P3 prove the WRITE was refused rather than the whole CSR being
//     unreachable.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // capture the privileged values first
    csrr x10, 0x7c1                        // pcc_length, expect FFFFFFFFFF at reset
    csrr x11, 0x7c0                        // pcc_base
    csrr x12, 0x7c3                        // mepcc_length
    csrr x17, 0x7c2                        // mepcc_base

    .insn r 0x7b, 0x0, 0x00, x0, x0, x0    # veda.droppriv -- one-way, no return

    li   x6, 0x40
    csrw 0x7c1, x6                         // must NOT take effect
    csrr x13, 0x7c1
    li   x6, 0xBAD
    csrw 0x7c0, x6                         // must NOT take effect
    csrr x14, 0x7c0
    li   x6, 0x80
    csrw 0x7c3, x6                         // must NOT take effect
    csrr x15, 0x7c3
    // 0x7C2 added after its mutant SURVIVED: the first draft wrote three of the
    // four CSRs, so the fourth's gate was unverified. Four-of-three is the same
    // shape as the atomic/sealed omission the census caught one increment ago.
    li   x6, 0xBEEF
    csrw 0x7c2, x6                         // must NOT take effect
    csrr x19, 0x7c2

    mv   x16, x20                          // trap count -- must be 0

1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
