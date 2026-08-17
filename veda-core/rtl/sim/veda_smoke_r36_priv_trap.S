#include "veda_priv_macros.h"
.section .text
.global _start
// R36/R39 -- THE PRIVILEGE MODEL, NOW THE ONE THE SPECIFICATION DEFINES.
//
// This test used to PIN the opposite behaviour, deliberately, because which
// answer was correct was the open question. It is answered now, and the answer
// was forced rather than chosen:
//
//   * $priv had exactly one writer -- veda.droppriv, Custom-3, one-way, with no
//     trap arm and no mret arm. The model defines neither the instruction nor
//     the opcode; both appear ZERO times in it.
//   * Milestone 4's addendum justified that on one ground: "real mret is a
//     trap-return semantic this core has no trap to return from". Milestone 9
//     built the traps and MRET. The premise expired; the instruction did not.
//   * And the layer had NO generic CSR privilege check at all, so every one of
//     its fourteen Machine-only CSRs -- mtvec included -- was readable and
//     writable from unprivileged code.
//
// So the RTL moved to the model, not the model to the RTL. Nothing had to be
// specified: trap raises to Machine, mret restores from mstatus.MPP, software
// drops privilege by writing MPP and executing mret, and a CSR access below the
// address's own privilege is an illegal instruction.
//
//   x10  populate BEFORE the drop      -- 1, the control: it works while privileged
//   x11  populate AFTER the drop       -- 0, refused
//   x12  0x1234 if the TRAP HANDLER IS PRIVILEGED -- the property the old model
//        could not provide, and the reason no operating system could have run here
//   x15  stays 0xBAD if a Machine CSR read from User raises Illegal_Instruction
//   x17  0x600D if that refusal carried mcause 0x02
//   x14  the LAST trap's mcause -- must be 0x08, "Environment call from U-mode".
//        It was hardcoded 0x0B, "from Machine mode", for every ecall regardless
//        of privilege, so a compartment's syscall announced itself to the
//        handler as the kernel's own.
//   x20  traps -- exactly 4
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x20, 0
    li   x12, 0
    li   x14, 0
    li   x15, 0xBAD
    li   x17, 0

    // CONTROL: privileged populate works
    li   x1, 90
    li   x2, 0x80010C000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 90
    .insn i 0x0b, 0x5, x1, x1, 0          // bind c1, 90 -- succeeds only if the populate did
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  // cgettag c1 -- 1 while privileged

    VEDA_DROP_TO_USER(x28, x29)           // R36: mstatus.MPP = User, then mret

    // (1) Now unprivileged: a populate must be refused
    li   x1, 91
    li   x2, 0x80010D000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   // must trap
    // (2) and the object therefore does not exist
    li   x1, 91
    // c9, NOT c11. The first draft used c11 and read tag 1 -- because c11 is a
    // SEEDED FIXTURE and the suite runs with +veda_fixtures, so a FAILED bind
    // leaves the fixture's own tag standing and the test measures the fixture
    // instead of the bind. c9 is outside the fixture range on both layers,
    // which R24 established when it needed exactly this property.
    .insn i 0x0b, 0x5, x9, x1, 0          // bind c9, 91 -- must trap, object not found
    .insn r 0x5b, 0x0, 0x03, x11, x9, x0  // cgettag c9 -- must be 0

    // (3) R39: a Machine-only CSR READ from User is an illegal instruction.
    //     Reads are gated, not just writes -- that is what check_CSR_priv says,
    //     and the old layer returned the value silently.
    csrr x15, 0x7c1                        // if this executes, x15 stops being 0xBAD

    // (4) R36: and the ecall that follows must announce U-mode, not M-mode.
    ecall

1:  j 1b

trap_handler:
    addi x20, x20, 1
    // Every instruction in this handler is itself privileged, which is the
    // whole point: on the old model none of them could run after a drop.
    csrr x14, mcause
    // Is the handler privileged? mscratch, deliberately -- it is Machine-only
    // and has no architectural side effect. The earlier draft probed 0x7C2
    // (mepcc_base) instead, which on the FIXED hardware actually lands, and a
    // landed 0x1234 in mepcc_base is restored into PCC by this very mret. The
    // probe would have broken the machine it was measuring.
    li   x6, 0x1234
    csrw mscratch, x6
    csrr x12, mscratch
    li   x6, 0x02
    bne  x14, x6, not_illegal
    li   x17, 0x600D
not_illegal:
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
