.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // D5 (DESIGN_07 Tier G) -- the CRBR saved shadow is released by NO exit
    // other than xret, and installed by ANY later xret.
    //
    // The RTL half of the finding. $veda_saved_region had reset, trap-capture
    // and mret arms and NO OCRETURN arm, while the mret restore arm on
    // $veda_current_region fires on the SENTINEL ALONE -- no depth term, no
    // owner term. OCRETURN is the architecture's SECOND exit from a trap
    // handler and the only one the shipped switcher takes
    // (runtime/veda_sched_asm.S), so a handler entered from a region-1
    // compartment and left by OCRETURN strands saved_region = 1, and the next
    // mret the machine executes -- by unrelated region-0 code, for an
    // unrelated reason -- installs region 1 as the current region.
    //
    // Measured on Sail before the fix, by instruction trace:
    //   [72] ocreturn c8   -> current_region 0, saved_region 1   (stranded)
    //   [77] ecall         -> no capture (the guard is current != 0)
    //   [83] mret          -> current_region 1                   (installed)
    //
    // Same structure as veda_smoke_r10_crbr_roundtrip.S, with exactly one
    // change: the handler leaves by OCRETURN instead of mret, and an ordinary
    // region-0 ecall/mret pair follows. Object_IDs match that file (region-1
    // CODE/DATA = (1<<24)|20 / |21, authority 45, sentry source 46) because
    // each program runs in its own simulation.
    // ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0
    li   x29, 0                            // trap counter

    // CONTROLS: the machine starts in region 0 with an EMPTY shadow.
    csrr x10, 0x7C6
    li   t2, 0
    bne  x10, t2, fail
    csrr x17, 0x7C7
    li   t2, 0xFFFFF
    bne  x17, t2, fail

    // -- region-0 SENTRY the handler will leave through.
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 46
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 46
    .insn i 0x0b, 0x5, x8, x1, 0
    .insn r 0x5b, 0x1, 0x15, x9, x8, x0   // csealentry c9, c8

    // -- region-1 compartment: CODE (Execute|Invoke) and DATA (Invoke-only).
    la   t0, compartment_r1
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 16777236
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 16777237
    li   x2, 0x8002000000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 45
    li   x2, 0x8001090000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 16777236
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 16777237
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, 45
    .insn i 0x0b, 0x5, x2, x1, 0
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   // ocinvoke -> region 1
    j    fail
.balign 4
compartment_r1:
    csrr x11, 0x7C6                        // CONTROL: inside, region is 1
    li   t2, 1
    bne  x11, t2, fail
    ecall                                  // the shadow captures region 1
    j    fail                              // the handler must NOT mret back here
.balign 4
return_landing:
    // Reached by the handler's OCRETURN. The trap frame was abandoned.
    csrr x14, 0x7C6                        // expect 0 -- this is a region-0 sentry
    li   t2, 0
    bne  x14, t2, fail
    csrr x18, 0x7C7                        // THE MEASUREMENT: released, or stranded?
    li   t2, 0xFFFFF
    bne  x18, t2, fail

    // An ordinary, unrelated region-0 trap returned by an ordinary mret. It
    // captures nothing, so it can only install what someone else left behind.
    li   x29, 1
    ecall
after_mret:
    csrr x19, 0x7C6                        // THE CONSEQUENCE: 0, or a stale 1?
    li   t2, 0
    bne  x19, t2, fail
    csrr x22, 0x7C7
    li   t2, 0xFFFFF
    bne  x22, t2, fail
    li   x20, 0x600D
    j    done
.balign 4
trap_handler:
    li   t2, 1
    beq  x29, t2, second_trap
    // trap 1, taken inside region 1.
    csrr x15, 0x7C6                        // CONTROL: handler runs in region 0
    li   t2, 0
    bne  x15, t2, fail
    csrr x16, 0x7C7                        // CONTROL: the shadow did capture
    li   t2, 1
    bne  x16, t2, fail
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0   // ocreturn c9 -- leave WITHOUT mret
    j    fail
second_trap:
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    li   x21, 0xBAD
done:
1:
    j 1b
