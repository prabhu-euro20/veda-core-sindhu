#include "veda_priv_macros.h"
.section .text
.global _start
_start:
    // ═══ R50 increment 2 -- THE CROSSING CLEARS THE CAPABILITY FILE ════════
    //
    // R50 measured the possession channel and left it open: OCInvoke's only
    // capability write is the IDC, OCReturn writes none, and the dereference
    // checker has ZERO domain terms -- so a callee needs no authority at all,
    // it simply uses a register the caller left bound. R48 closed the MINT
    // channel; this closes the POSSESSION one.
    //
    // THE ABI: CSR 0x8CA veda_xretain. Bit i set means capability register i
    // SURVIVES the next crossing. Never written means zero means retain
    // NOTHING, so silence means clear and never leak. The mask is
    // SELF-CONSUMING, so it cannot survive to apply to a later crossing --
    // a compartment that wants to pass capabilities onward must set the CSR
    // ITSELF, from inside its own PCC window.
    //
    // THIS FILE CARRIES THE DISCRIMINATION. The other 50 crossings in the RTL
    // corpus declare RETAIN ALL because they measure other mechanisms; if the
    // clear were deleted every one of them would still pass. Round 1 below
    // fails if the clear is absent, and round 2 fails if the mask is ignored
    // and everything is cleared unconditionally.
    //
    // Integer registers are untouched -- the clear is capability-file only --
    // so the evidence survives both crossings in x-registers.
    //
    // Object_IDs 140..144: verified unseeded. The RTL seeds 1, 2, 60, 104,
    // 105, 106, 108, 109, 257, 519, 520, and it indexes with local[7:0], so
    // 257/519/520 occupy low bytes 1/7/8. 140..144 collide with none of them.
    //
    // Every register named by NUMBER: this project has three times turned a
    // check into a comparison of a register with itself by trusting an ABI
    // alias (t4 IS x29, s11 IS x27, t3 IS x28).
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0                            // cumulative trap count
    li   x26, 0                            // last mtval
    li   x16, 0                            // round
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0
    li   x25, 0

    // ─── the type authority (seal/unseal) ─────────────────────────────────
    li   x1, 140
    li   x2, 0x8001100000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    // ─── the compartment's CODE object ────────────────────────────────────
    la   x6, compartment
    slli x6, x6, 32
    li   x7, 0x02000402                    // Length 0x200, Perms EXECUTE|INVOKE
    or   x2, x6, x7
    li   x1, 141
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    // ─── the compartment's DATA object (its IDC) ──────────────────────────
    li   x1, 142
    li   x2, 0x8001110000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    // ─── the way back: an UNBOUNDED sentry over `landing`. The compact
    //     Populate's Length field is 16 bits and cannot express the 40-bit
    //     sentinel, so this uses the wide path, whose Length/Perms come from
    //     veda_attr = Length[55:16] | Perms[15:0].
    li   x7, 0xFFFFFFFFFF
    slli x7, x7, 16
    ori  x7, x7, 0x0402
    csrw 0x7C4, x7
    la   x8, landing
    li   x1, 143
    .insn r 0x0b, 0x0, 0x04, x5, x1, x8

    // ─── the caller's SECRET, the thing the callee must not reach ─────────
    li   x1, 144
    li   x2, 0x800112000020000C            // Perms LOAD|STORE
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    // ═══ R75/R76 -- BOOT DECLARES WHO MAY BIND ═══════════════════════════════
    // Ambient creation stamps VEDA_DOMAIN_BOOT now, so an object is no longer
    // public by accident. This file needs FIVE declarations and the reason is
    // structural: `setup:` below is RE-ENTERED after the first OCReturn, so on
    // the second pass every one of these binds runs from INSIDE a compartment,
    // whose identity is the sentry's object -- region 0.
    li   x2, 0
    li   x1, 140
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 141
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 142
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 143
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2
    li   x1, 144
    .insn r 0x0b, 0x1, 0x06, x5, x1, x2

    bne  x27, x0, done                     // no trap is allowed in setup

.balign 4
setup:
    // Re-entered once, after round 1's OCReturn cleared the whole capability
    // file. The ODT entries persist; only the registers were destroyed.
    li   x1, 140
    .insn i 0x0b, 0x5, x7, x1, 0           // veda.bind c7, 140  -- type authority
    li   x1, 141
    .insn i 0x0b, 0x5, x0, x1, 0           // veda.bind c0, 141  -- CODE
    li   x1, 142
    .insn i 0x0b, 0x5, x1, x1, 0           // veda.bind c1, 142  -- DATA
    .insn r 0x5b, 0x1, 0x10, x3, x0, x7    // cseal c3, c0, c7
    .insn r 0x5b, 0x1, 0x10, x4, x1, x7    // cseal c4, c1, c7   -- matching otype
    li   x1, 143
    .insn i 0x0b, 0x5, x12, x1, 0          // veda.bind c12, 143
    .insn r 0x5b, 0x1, 0x15, x13, x12, x0  // csealentry c13     -- the way back
    li   x1, 144
    .insn i 0x0b, 0x5, x10, x1, 0          // veda.bind c10, 144 -- the SECRET
    li   x8, 0
    li   x9, 0xC0FFEE
    .insn r 0x0b, 0x3, 0x01, x9, x10, x8   // ocs.d c10 -- plant the secret

    li   x19, 1
    beq  x16, x19, round2

    // ═══ ROUND 1 -- retain ONLY the sentry. c10 must NOT survive. ═════════
    li   x31, 0x2000                       // bit 13
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    // ocinvoke c3, c4
    j    done

.balign 4
round2:
    // ═══ ROUND 2 -- retain the sentry AND c10. The read must SUCCEED. ═════
    // This is the over-refusal guard, and it is the load-bearing half: a core
    // that cleared unconditionally, ignoring the mask entirely, would pass
    // round 1 for entirely the wrong reason.
    li   x31, 0x2400                       // bits 13 and 10
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4    // ocinvoke c3, c4
    j    done

.balign 4
compartment:
    // Narrowed PCC, a different compartment. No ordinary load or store may
    // appear below -- the purecap rule refuses every one of them inside a
    // live compartment.
    li   x8, 0
    li   x18, 0
    .insn r 0x0b, 0x3, 0x00, x18, x10, x8  // ocl.d through the CALLER's c10
    li   x19, 1
    beq  x16, x19, r2check
    mv   x20, x27                          // round 1: trap count
    mv   x21, x26                          // round 1: mtval
    mv   x22, x18                          // round 1: what was read
    li   x16, 1
    li   x31, 0                            // nothing survives the return
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0   // ocreturn c13
    j    done

.balign 4
r2check:
    mv   x23, x27                          // round 2: trap count (must not grow)
    mv   x24, x18                          // round 2: what was read
    li   x16, 2
    li   x31, 0
    csrw 0x8CA, x31
    .insn r 0x5b, 0x1, 0x16, x0, x13, x0   // ocreturn c13
    j    done

.balign 4
landing:
    li   x19, 1
    beq  x16, x19, rebuild
    j    done

.balign 4
rebuild:
    // The callee's IDC must NOT have come back: OCRETURN installs none, and
    // c15 is deliberately NOT exempt on the return leg -- the exemption on
    // the call leg exists only because OCInvoke overwrites c15 anyway.
    .insn r 0x5b, 0x0, 0x03, x25, x15, x0  // cgettag c15 -- must be 0
    j    setup

.balign 4
trap_handler:
    addi x27, x27, 1
    csrr x26, mtval
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret

done:
1:
    j 1b
