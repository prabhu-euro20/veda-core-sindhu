.section .text
.global _start
// R26 -- AUTHORITY IS A NAME, NOT A BOUND.
//
// Seven security gates used to answer "does this code hold machine authority?"
// by testing veda_pcc_length against VEDA_PCC_UNBOUNDED. Length is a number
// software chooses: enter a compartment on a code object whose Length IS the
// sentinel and the predicate reads true, so all seven open at once and the
// compartment can rewrite its own execution bounds, redirect mtvec, and forge
// its trap return.
//
// THIS TEST IS A SINGLE-TERM DISCRIMINATOR, and that is the whole design of it.
// Inside the compartment, veda_pcc_length IS 0xFFFFFFFFFF -- identical to the
// value it has at boot. So the length term reads exactly the same in both
// cases and CANNOT be what refuses. The only thing that differs is
// veda_pcc_object: NONE at boot, and the entered object's name inside the
// compartment. Nothing else can fire.
//
// P1 baseline, before any crossing: object is NONE, so a gated CSR write must
//    SUCCEED. This is what proves the gate is not simply always-refusing, and
//    it is also the "before" half of the discriminator.
// P2 the escape: enter a compartment on a SENTINEL-LENGTH object, then write
//    the same CSR. Before R26 this succeeded and the machine was open. It must
//    now be refused, with the length term reading identical to P1.
// P3 mtvec, the same test on the positive-polarity gate -- a compartment that
//    can redirect mtvec owns every future trap.
// P4 control: after returning, the write must work again, proving the refusal
//    tracked the compartment and did not simply latch.
//
// Object 30 is minted fresh with Length = VEDA_PCC_UNBOUNDED deliberately.
// That object is legal and stays legal -- reserving it was tried and refused,
// because 22 Sail and 14 RTL tests construct exactly it to return to unbounded
// PCC. R26 does not forbid the object; it stops the object from conferring
// authority.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    // ---------------- P1: baseline, outside any compartment ----------------
    // 0x7C3 (veda_mepcc_length), NOT 0x7C1. Writing a small value to 0x7C1
    // narrows the PCC of the code CURRENTLY EXECUTING, so the very next fetch is
    // out of bounds and the machine trap-loops forever -- a first draft of this
    // test did exactly that and produced 116 traps. 0x7C3 is on the same gate,
    // is the trap-RETURN forge (so it is the more security-relevant of the two),
    // and does not touch the running PCC.
    li   x6, 0x40
    csrw 0x7c3, x6
    csrr x10, 0x7c3                        // must read back 0x40 -- the write took
    li   x6, 0xFFFFFFFFFF
    csrw 0x7c3, x6                         // restore before crossing
    csrr x21, 0x7c3                        // sanity: back to the sentinel

    // ---------------- build a sentinel-Length code object ----------------
    // POPULATE.FAST, not the compact form. The compact descriptor's Length field
    // is only 16 bits and tops out at 0xFFFF, so it CANNOT express the 40-bit
    // sentinel -- a first draft of this test used it and produced a garbage
    // object, a failed crossing and a trap storm. veda_attr (CSR 0x7C4) carries
    // {Length[39:0], Perms[15:0]}; rs2 carries the full Base.
    li   x3, 0xFFFFFFFFFF                  // the 40-bit sentinel Length
    slli x3, x3, 16
    ori  x3, x3, 0x0001                    // Perms = Execute
    csrw 0x7c4, x3                         // veda_attr := {Length, Perms}
    li   x1, 30
    li   x2, 0x80010600                    // Base
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast 30

    li   x1, 30
    .insn i 0x0b, 0x5, x4, x1, 0          # veda.bind c4, 30
    // CSeal with a real sealing AUTHORITY, not CSealEntry. CSealEntry mints the
    // reserved SENTRY otype, which is what OCRETURN consumes -- OCInvoke refuses
    // it. A first draft used csealentry here and the crossing was refused, so the
    // compartment was never entered and the test proved nothing while looking
    // like a mechanism failure.
    li   x1, 40
    li   x3, 0x0300                        // Permit_Seal | Permit_Unseal
    csrw 0x7c4, x3
    li   x1, 40
    li   x2, 0x80010800
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # populate 40 -- the sealing authority
    li   x1, 40
    .insn i 0x0b, 0x5, x7, x1, 0          # veda.bind c7, 40
    .insn r 0x5b, 0x1, 0x10, x4, x4, x7   # cseal c4, c4, c7

    // ---------------- P2 + P3: inside the sentinel compartment ----------------
    .insn r 0x5b, 0x1, 0x12, x0, x4, x4   # ocinvoke c4, c4 -- PCC length := sentinel, object := 30
compartment:
    li   x6, 0x40
    csrw 0x7c3, x6                         // MUST be refused: object is no longer NONE
    csrr x11, 0x7c3                        // must still read the sentinel
    la   x6, hijacked
    csrw mtvec, x6                         // MUST be refused
    csrr x12, mtvec                        // must still be trap_handler
    j    1f

1:  mv   x13, x20                          // trap count so far
    j 2f

hijacked:
    li   x14, 0xBAD                        // must NEVER execute
2:
    li   x15, 0x600D
1:  j 1b

trap_handler:
    addi x20, x20, 1
    csrr x29, mepc
    addi x29, x29, 4
    csrw mepc, x29
    mret
