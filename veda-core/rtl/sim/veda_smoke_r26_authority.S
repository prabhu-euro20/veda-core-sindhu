.section .text
.global _start
// R26 -- AUTHORITY IS A NAME, NOT A BOUND.
//
// Seven security gates used to answer "does this code hold machine authority?"
// by testing veda_pcc_length against VEDA_PCC_UNBOUNDED. Length is a number
// software chooses: enter a compartment on a code object whose Length IS the
// sentinel and the predicate reads true, so the gates open and the compartment
// can rewrite its own execution bounds and redirect every future trap.
//
// SINGLE-TERM DISCRIMINATOR, and that is the whole design. Inside the
// compartment veda_pcc_length IS 0xFFFFFFFFFF -- byte-identical to its value at
// boot. So the length term reads the SAME in both cases and cannot be what
// refuses. Only veda_pcc_object differs: NONE at boot, object 30 inside.
//
// WHAT OCINVOKE ACTUALLY DEMANDS -- read from $veda_ocinvoke_violation rather
// than guessed, after two earlier drafts failed by guessing:
//   both capabilities TAGGED and SEALED, with the SAME otype
//   both carrying PERM_INVOKE (bit 10)
//   rs1 (CODE) must have EXECUTE (bit 1); rs2 (DATA) must NOT
//   the region must be RT-resident, generation current, object resident
// Earlier drafts passed one capability twice, which fails on the data-side
// EXECUTE term alone, and never set PERM_INVOKE at all.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // ---------------- P1: baseline, outside any compartment ----------------
    // 0x7C3 (mepcc_length), not 0x7C1: writing a small value to 0x7C1 narrows
    // the PCC of the code CURRENTLY RUNNING, so the next fetch is out of bounds
    // and the machine trap-loops. 0x7C3 is on the same gate and is the
    // trap-RETURN forge, so it is the more security-relevant of the two.
    li   x6, 0x40
    csrw 0x7c3, x6
    csrr x10, 0x7c3                        // must read 0x40 -- the gate is open out here
    li   x6, 0xFFFFFFFFFF
    csrw 0x7c3, x6
    csrr x21, 0x7c3                        // restored to the sentinel

    // ---------------- the sealing authority ----------------
    // Length MUST be non-zero: cseal demands cs2.Offset < cs2.Length, because the
    // otype it mints IS the authority's Offset and an authority may only mint
    // otypes inside its own range. An authority of Length 0 authorises nothing --
    // and cseal still writes every OTHER field, setting only the TAG from the
    // authorisation result. So an unauthorised seal yields a capability that
    // LOOKS correct in every field and is simply untagged. That is what the first
    // run showed: perms 0x402/0x40C exact, otypes matching, resident, current --
    // and tag 0 on both, refusing at the very first term of the chain.
    li   x3, 0x40
    slli x3, x3, 16
    ori  x3, x3, 0x0300                    // Length=0x40, Permit_Seal | Permit_Unseal
    csrw 0x7c4, x3
    li   x1, 40
    li   x2, 0x80010800
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # populate.fast 40 -- the seal authority
    li   x1, 40
    .insn i 0x0b, 0x5, x7, x1, 0          # bind c7, 40

    // ---------------- the CODE object: Length = the sentinel ----------------
    // Base is the compartment label itself, so PCC covers the code that runs.
    li   x3, 0xFFFFFFFFFF
    slli x3, x3, 16
    ori  x3, x3, 0x0402                    // EXECUTE (bit 1) | INVOKE (bit 10)
    csrw 0x7c4, x3
    li   x1, 30
    la   x2, compartment
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # populate.fast 30 -- Length = SENTINEL
    li   x1, 30
    .insn i 0x0b, 0x5, x4, x1, 0          # bind c4, 30
    .insn r 0x5b, 0x1, 0x10, x4, x4, x7   # cseal c4, c4, c7

    // ---------------- the DATA object: no EXECUTE ----------------
    li   x3, 0x40
    slli x3, x3, 16
    ori  x3, x3, 0x040C                    // LOAD | STORE | INVOKE, NO execute
    csrw 0x7c4, x3
    li   x1, 31
    li   x2, 0x80010900
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # populate.fast 31
    li   x1, 31
    .insn i 0x0b, 0x5, x6, x1, 0          # bind c6, 31
    .insn r 0x5b, 0x1, 0x10, x6, x6, x7   # cseal c6, c6, c7  -- SAME authority, same otype

    li   x18, 0xA11E                      // marker: reached the crossing
    .insn r 0x5b, 0x1, 0x12, x0, x4, x6   # ocinvoke c4(code), c6(data)

compartment:
    // PCC length is now the sentinel -- identical to its boot value.
    li   x6, 0x40
    csrw 0x7c3, x6                         // MUST be refused: object is no longer NONE
    csrr x11, 0x7c3
    la   x6, hijacked
    csrw mtvec, x6                         // MUST be refused
    csrr x12, mtvec
    li   x15, 0x600D
1:  j 1b

hijacked:
    li   x14, 0xBAD                        // must NEVER execute
1:  j 1b

trap_handler:
    // Record each refusal's cause SEPARATELY. Two different mechanisms are
    // supposed to be refusing here and a single shared register would let one
    // of them go unmeasured -- the exact shape of mistake this corpus has been
    // bitten by before.
    addi x20, x20, 1
    csrr x22, mcause
    li   x28, 1
    bne  x20, x28, 1f
    mv   x23, x22                          // cause of refusal 1 (mepcc_length)
    j    2f
1:  mv   x24, x22                          // cause of refusal 2 (mtvec)
2:  csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
