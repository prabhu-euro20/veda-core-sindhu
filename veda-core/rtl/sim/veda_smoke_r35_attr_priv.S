#include "veda_priv_macros.h"
.section .text
.global _start
// R35 -- veda_attr (CSR 0x7C4) had no privilege term on this layer.
//
// Four of the five compartment-state CSR write arms carry && $priv. R27 added it
// to those four; this one sat between them and did not get it. Sail refuses the
// write outright -- csrPriv(0x7C4) is 0b11, Machine-only by the RISC-V
// convention, enforced by the generic check_CSR_priv before any Veda clause runs
// -- so this was an RTL-only authority grant.
//
// WHAT IT GRANTED: veda_attr supplies Length and Perms to Populate-Fast. It is
// not a mint. But an unprivileged principal could choose the Length and Perms of
// an object a later PRIVILEGED Populate-Fast would mint -- control over the
// contents of someone else's mint.
//
// R39 UPDATE. This test used to assert a trap count of ZERO, on the ground that
// a refused CSR write is "a silent no-op here, matching the four arms R27
// gated". Those four were also wrong, for the same reason: check_CSR_priv sits
// ABOVE every Veda write_CSR clause, so the model raises Illegal_Instruction and
// never reaches the clause whose silence was being mirrored. The refusal is now
// a real trap on both layers, and the READ is refused too -- which is why the
// read-back has to be done by the handler, the only privileged code left.
//
//   x10  attr read back while privileged   -- the write LANDS (the control:
//        without it a layer that wired 0x7C4 shut would pass)
//   x11  stays 0xBAD -- the unprivileged READ never executed either
//   x12  the value the unprivileged write tried to install
//   x13  the privileged read-back: must still be x10, must never be x12
//   x20  traps -- exactly 3
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0
    li   x11, 0xBAD
    li   x13, 0

    li   x6, 0x0040
    slli x6, x6, 16
    ori  x6, x6, 0x000C                    // Length 0x40, Perms Load|Store
    csrw 0x7c4, x6
    csrr x10, 0x7c4                        // CONTROL: privileged write lands

    VEDA_DROP_TO_USER(x28, x29)            // R36: the architected drop

    li   x12, 0xFFFFFFFFFF                 // the escalation attempt: unbounded Length
    slli x12, x12, 16
    ori  x12, x12, 0x0402                  // and Execute|Invoke
    csrw 0x7c4, x12                        // 1 -- must NOT land
    csrr x11, 0x7c4                        // 2 -- and must not even be readable
    ecall                                  // 3 -- ask a privileged handler to look

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
    csrr x13, 0x7c4                        // privileged read-back
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
