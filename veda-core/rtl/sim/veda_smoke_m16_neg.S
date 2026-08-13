.section .text
.global _start
_start:
    // RTL Milestone 16 negative control: proves the real bug this
    // milestone fixes (ARCHITECTURE_IMPROVEMENT_FINDINGS.md Finding 2).
    // Destroy the same Object_ID 256 times in a loop -- before this
    // milestone, this wrapped the 8-bit generation counter exactly back
    // to a stale capability's own cached value, and a subsequent
    // re-populate let that stale capability keep dereferencing memory it
    // should have lost access to at the very first Destroy (empirically
    // reproduced before any fix was designed). This test proves the
    // slot is now permanently retired instead: the re-populate attempt
    // is silently refused, and the stale capability's own later use
    // correctly hard-traps.
    // RTL-11 (R14): the retired-slot refusal now TRAPS, so the handler has to
    // be installed BEFORE it rather than just before the stale access below.
    // Two traps are expected now, not one, and the handler tells them apart:
    // the first is the refused re-populate (resume past it), the second is the
    // stale access this test has always been about.
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0
    la   x5, array_a
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 200
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 200
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0   -- sanity: x8 = 0xAAAA...

    li   x6, 256
    li   x1, 200
destroy_loop:
    .insn r 0x0b, 0x1, 0x03, x9, x1, x0  # veda.odt.destroy x9, x1
    addi x6, x6, -1
    bnez x6, destroy_loop

    // Fixed behavior: the slot is now permanently retired (generation
    // saturated at 0xFF), so this re-populate must be silently refused
    // -- object B is never actually written.
    la   x5, array_b
    slli x5, x5, 32
    li   x9, 0x00080004
    or   x5, x5, x9
    li   x1, 200
    mv   x2, x5
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 (must be REFUSED)


    // Use the ORIGINAL, stale c0 directly. Fixed: since the re-populate
    // above was refused, the slot stayed invalid, so this must
    // hard-trap (a real OCL.D Tag/generation violation), not succeed.
    li   x18, 1
    bne  x20, x18, 1f                      // the refused re-populate trapped
    li   x18, 2
    bne  x21, x18, 1f                      // mcause 2 = illegal instruction
    li   x23, 0x600D
    li   x2, 0
fault_instr:
    .insn r 0x0b, 0x3, 0x00, x8, x0, x2  # ocl.d x8, x2, c0
    li   x22, 0xDEAD         # reached only if the OLD, buggy behavior recurred
    j    done

trap_handler:
    addi x20, x20, 1
    csrr x21, mcause
    li   x18, 2
    beq  x20, x18, stale_access_trap
    // trap 1: the refused re-populate. Resume just past it.
    csrr x17, mepc
    addi x17, x17, 4
    csrw mepc, x17
    mret
stale_access_trap:
    li   x22, 0x600D         # FIXED: the stale access correctly trapped
done:
1:
    j 1b

.section .data
.align 3
array_a:
    .dword 0xAAAAAAAAAAAAAAAA
array_b:
    .dword 0xBBBBBBBBBBBBBBBB
