#include "veda_priv_macros.h"
.section .text
.global _start
_start:
    // ═══ R48 -- THE ODA IS CLEARED AT EVERY COMPARTMENT CROSSING ═══════════
    //
    // OCInvoke narrows PCC, installs a fresh IDC, reloads the CRBR and clears
    // the SSC. It left veda_oda untouched -- and the argument against that was
    // already written down, for the SSC, inside the OCInvoke clause itself,
    // naming "ODA/TSC's own untouched-by-OCInvoke convention" as the thing an
    // SSC must not follow. Nobody turned it back on the ODA.
    //
    // Pre-R47 it was moot: an unscoped ODA reached all of memory from anywhere.
    // R47 gave it a window, so inheriting it is inheriting MINT AUTHORITY OVER
    // THE CALLER'S MEMORY. MEASURED on Sail before the fix -- a User compartment
    // holding nothing but a code and a data capability DESTROYED the caller's
    // object and MINTED a fresh descriptor over the caller's window, with ZERO
    // traps.
    //
    // This is the RTL half. It cannot live in the differential harness: that
    // harness runs with test_fixtures FALSE by design (R24), the region table
    // has NO software write path at all, and OCInvoke requires an RT-resident
    // region -- so every OCInvoke REGION_FAULTs there. See difftest/blocked/
    // and DESIGN_07 R51.
    //
    // Object_IDs 130..135: verified unseeded (the RTL seeds 1, 2, 60, 104, 105,
    // 106, 108, 109, 257, 519, 520).
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x25, 0                            // trap count

    // ─── the authority, scoped to W = [0x80011000, 0x80011040) ────────────
    li   x1, 130
    li   x2, 0x8001100000400080            // Perms 0x0080 = PERM_ACCESS_SYSTEM_REGISTERS
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 130
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, 130
    .insn r 0x5b, 0x1, 0x13, x2, x1, x0    // ospecialrw c2, ODA, c1

    // ─── the compartment fixture ──────────────────────────────────────────
    la   t0, callee_entry
    slli t0, t0, 32
    li   t1, 0x00400402                    // Len 0x40, Perms EXECUTE|INVOKE
    or   t0, t0, t1
    li   x1, 132
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // CODE
    li   x1, 133
    li   x2, 0x800107000040040C            // DATA  Perms LOAD|STORE|INVOKE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 134
    li   x2, 0x8001080000400300            // type authority
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 132
    .insn i 0x0b, 0x5, x5, x1, 0
    li   x1, 133
    .insn i 0x0b, 0x5, x6, x1, 0
    li   x1, 134
    .insn i 0x0b, 0x5, x7, x1, 0
    .insn r 0x5b, 0x1, 0x10, x8, x5, x7    // cseal c8, c5, c7
    .insn r 0x5b, 0x1, 0x10, x9, x6, x7    // cseal c9, c6, c7

    VEDA_DROP_TO_USER(x28, x29)            // R36: the architected drop

    // ═══ CONTROL 0 -- the delegated path genuinely works BEFORE the crossing.
    // Without this a machine whose ODA never worked at User at all would satisfy
    // every assertion below for entirely the wrong reason.
    li   x1, 131
    li   x2, 0x800110000020000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    bne  x25, x0, done                     // no trap allowed here
    li   x20, 0x600D

    // R50 increment 2: this file predates the crossing's retain mask and
    // measures a different mechanism, so it declares RETAIN ALL. The burden
    // of proving the clear works sits on veda_smoke_r50i2_crossing_clear.S.
    li   x31, 0xFFFF
    csrw 0x7CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x8, x9    // ocinvoke c8, c9

.balign 4
callee_entry:
    // Narrowed PCC, still User, a different compartment. No ordinary load or
    // store may appear below: the purecap rule refuses every one of them inside
    // a live compartment.
    li   x1, 135
    li   x2, 0x800110000010000C            // inside the CALLER's window
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2    // MUST NOW BE REFUSED

    // ═══ CONTROL 1 -- the over-refusal guard, and it is the load-bearing one.
    // The callee must still do what the architecture still owes it: use the IDC
    // OCInvoke handed it. A core that broke OCInvoke, or that trapped
    // everything after any crossing, passes the refusal above and fails here.
    li   x11, 0x5A5A
    li   x12, 0
    .insn r 0x0b, 0x3, 0x01, x11, x15, x12 // ocs.d c15, x12, x11
    li   x13, 0
    .insn r 0x0b, 0x3, 0x00, x13, x15, x12 // ocl.d c15, x12, x13
    mv   x22, x13
    ecall

.balign 4
trap_handler:
    csrr x27, mcause
    li   x26, 8
    beq  x27, x26, verdict
    li   x26, 11
    beq  x27, x26, verdict
    addi x25, x25, 1
    mv   x21, x27                          // the callee's refusal cause
    csrr x26, mepc
    addi x26, x26, 4
    csrw mepc, x26
    mret

.balign 4
verdict:
    // Machine again. COUNTING A REFUSAL IS NOT CHECKING IT -- assert the effect.
    li   x1, 135
    .insn i 0x0b, 0x5, x10, x1, 1          // veda.bind.notrap c10, 135
    .insn r 0x5b, 0x0, 0x03, x23, x10, x0  // must be 0: nothing was minted
    li   x1, 131
    .insn i 0x0b, 0x5, x14, x1, 1          // veda.bind.notrap c14, 131
    .insn r 0x5b, 0x0, 0x03, x24, x14, x0  // must be 1: the caller's own work survived
done:
1:
    j 1b
