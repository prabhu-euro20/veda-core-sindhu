.section .text
.global _start
_start:
    // R64 -- the bind-side fault-identification channel, CSR 0x7C9.
    //
    // DESIGN_02:293-297: "The handler cannot identify which object faulted.
    // mtval carries {cap_idx, cause}, not an Object_ID ... it should be
    // resolved BEFORE `backing` is designed rather than after."
    //
    // CGetObjectID closed it for the COW fault, where a live capability exists.
    // It does NOT close it on the bind side: the residency trap passes the
    // destination register of a Bind that never completed, so no capability
    // names the faulting object.
    //
    // Every register named BY NUMBER. Three ABI-alias collisions in this
    // session (s11 IS x27, t3 IS x28, t4 IS x29) each turned a check into a
    // comparison of a value with itself.
    //   x27 trap counter   x26 last mtval   x25 sentinel   x17 handler temp
    //   x18..x24 results   x1..x10, x30 scratch
    // Objects 400 and 401 -> RTL slots 144 and 145; the fixtures seed 1, 2, 60,
    // 104, 105, 106, 108, 109, 257, 519 and 520 only.
    la   x30, trap_handler
    csrw mtvec, x30
    li   x27, 0
    li   x26, 0
    li   x25, 0xFFFFFFFFFFF
    li   x18, 0
    li   x21, 0
    li   x24, 0

    // CONTROL 1: resets to the SENTINEL, not zero. Object 0 is a legal name.
    csrr x18, 0x7C9
    bne  x18, x25, done
    li   x19, 0x600D

    // THE CHANNEL, case 1: a name that was never populated.
    li   x1, 400
    .insn i 0x0b, 0x5, x3, x1, 0            // veda.bind c3, 400
    li   x8, 1
    bne  x27, x8, done
    andi x8, x26, 0x1f
    li   x9, 0x05
    bne  x8, x9, done                       // OBJECT_NOT_FOUND
    csrr x20, 0x7C9                         // must be 400

    // FAIL-CLOSED: an ordinary trap that consulted no descriptor clears it.
    ecall
    li   x8, 2
    bne  x27, x8, done
    csrr x22, 0x7C9
    bne  x22, x25, done
    li   x21, 0x600D

    // THE CHANNEL, case 2: a residency fault mints nothing, so nothing else
    // can name the object -- the case DESIGN_02 actually asks for.
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C
    or   x2, x6, x7
    li   x1, 401
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     // populate 401
    li   x8, 2
    bne  x27, x8, done
    li   x1, 401
    .insn r 0x0b, 0x1, 0x05, x5, x1, x0     // page.out 401
    li   x8, 2
    bne  x27, x8, done
    li   x1, 401
    .insn i 0x0b, 0x5, x4, x1, 0            // veda.bind c4, 401
    li   x8, 3
    bne  x27, x8, done
    andi x8, x26, 0x1f
    li   x9, 0x0A
    bne  x8, x9, done                       // RESIDENCY_FAULT
    csrr x23, 0x7C9                         // must be 401
    .insn r 0x5b, 0x0, 0x03, x10, x4, x0    // cgettag -- nothing was minted
    bnez x10, done
    li   x24, 0x600D
    j    done
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
.section .data
.balign 64
arena:
    .space 64
