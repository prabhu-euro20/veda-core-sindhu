/* Veda-Core RTL test macros -- the architected way to leave Machine mode.
 *
 * R36 retired `veda.droppriv`. It was a one-instruction, one-way privilege
 * drop in the Custom-3 opcode space, and its own justification
 * (MILESTONE_PLAN.md, Milestone 4 addendum) was that "real mret is a
 * trap-return semantic this core has no trap to return from". Milestone 9
 * built the traps and MRET; the premise expired and the instruction outlived
 * it. The model never defined it, or the Custom-3 opcode, at all.
 *
 * What replaces it is not a Veda invention -- it is what every RISC-V hart
 * does, and what the Sail model this project builds against already
 * implements, so nothing had to be specified to adopt it:
 *
 *     mstatus.MPP <- 0b00 (User) ; mepc <- the resume label ; mret
 *
 * Two scratch registers, both DEAD after the macro. Pick registers that are
 * not live across the drop at the call site -- this file cannot check that
 * for you, and a register still holding a sentinel is exactly the kind of
 * quiet corruption that makes a negative test pass for the wrong reason.
 *
 * The local label 9 is used, and no test in this corpus defines one.
 *
 * WHAT CHANGES FOR A TEST THAT USED THE OLD INSTRUCTION. The drop is no
 * longer one-way. A trap now raises to Machine, so the HANDLER is privileged
 * even when the faulting instruction was not, and the handler's own mret
 * returns to whatever MPP holds -- User, for a trap taken from User. Tests
 * that asserted "the handler cannot do privileged things" were pinning the
 * old model and have been rewritten to assert the new one.
 */
#ifndef VEDA_PRIV_MACROS_H
#define VEDA_PRIV_MACROS_H

#define VEDA_DROP_TO_USER(ta, tb) \
    li   ta, 0x1800;              \
    csrc mstatus, ta;             \
    la   tb, 9f;                  \
    csrw mepc, tb;                \
    mret;                         \
9:

#endif
