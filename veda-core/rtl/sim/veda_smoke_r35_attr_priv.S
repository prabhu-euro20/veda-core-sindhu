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
//   x10  attr read back while privileged      -- the write LANDS
//   x11  attr read back after veda.droppriv   -- must be UNCHANGED
//   x12  the value the unprivileged write tried to install
//   x20  traps -- the RTL makes a refused CSR write a silent no-op here, matching
//        the four arms R27 already gated, so zero is correct and is asserted
//        rather than left unstated.
//
// The control is x10: without it a layer that simply wired 0x7C4 shut would pass.
_start:
    la   x5, trap_handler
    csrw mtvec, x5
    li   x20, 0

    li   x6, 0x0040
    slli x6, x6, 16
    ori  x6, x6, 0x000C                    // Length 0x40, Perms Load|Store
    csrw 0x7c4, x6
    csrr x10, 0x7c4                        // CONTROL: privileged write lands

    .insn r 0x7b, 0x0, 0x00, x0, x0, x0   // veda.droppriv -- one-way, $priv 1 -> 0

    li   x12, 0xFFFFFFFFFF                 // the escalation attempt: unbounded Length
    slli x12, x12, 16
    ori  x12, x12, 0x0402                  // and Execute|Invoke
    csrw 0x7c4, x12                        // must NOT land
    csrr x11, 0x7c4                        // must still read the privileged value

1:  j 1b
trap_handler:
    addi x20, x20, 1
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
