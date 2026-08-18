.section .text
.global _start
_start:
    // R63 -- the region half of an Object_ID was an IDENTITY on the read path
    // and a bare INDEX on the write path.
    //
    // R55 put rt_valid on veda.bind. VEDA_ODT_POPULATE's gates are
    // Machine-or-ODA, the executing pin, the ODA window and `retired` -- none of
    // them reads either RT bit -- so a Populate could name ANY in-window region.
    // Regions 4..7 reset to rt_odt_base = 0, which IS region 0's base, so the
    // local half alone picked the slot.
    //
    // Measured on the shipped Sail model before the fix: populate {5,200}
    // accepted with zero traps, bind {0,200} returning tag 1 and the prober's
    // own arena as its Base, bind {5,200} refused with REGION_FAULT. A
    // descriptor written under a name its author was then refused to read.
    //
    // This CORRECTS R56, which named the barrier as rt_resident[4] == false and
    // concluded a future RT-Populate was needed to reach it. It was reachable
    // with the shipped instruction set.
    //
    // Slot 200: the fixtures seed 1, 2, 60, 104, 105, 106, 108, 109, 257, 519
    // and 520, and nothing else.
    la   x30, trap_handler
    csrw mtvec, x30
    li   x29, 0
    li   x28, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0

    // CONTROL 1: slot 200 starts empty, so the plain name is refused.
    li   x1, 200
    .insn i 0x0b, 0x5, x3, x1, 0
    li   x7, 1
    bne  x29, x7, done
    andi x7, x28, 0x1f
    li   x6, 0x05
    bne  x7, x6, done                      // OBJECT_NOT_FOUND
    li   x20, 0x600D

    // THE FINDING: populate under a region that was never configured.
    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C                    // Len 0x20, Perms Load|Store
    or   x2, x6, x7
    li   x1, 83886280                      // (5 << 24) | 200
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 2
    bne  x29, x7, done                     // must trap. Before the fix: accepted.
    li   x21, 0x600D

    // CONTROL 2: and it wrote NOTHING -- the plain name is still empty, still
    // for the same reason, so that was a refusal and not a redirect.
    li   x1, 200
    .insn i 0x0b, 0x5, x4, x1, 0
    li   x7, 3
    bne  x29, x7, done
    andi x7, x28, 0x1f
    li   x6, 0x05
    bne  x7, x6, done
    .insn r 0x5b, 0x0, 0x03, x6, x4, x0    // cgettag -- must be 0
    bnez x6, done
    li   x22, 0x600D

    // CONTROL 3: a REAL region still works, so the gate is not simply refusing
    // every cross-region populate.
    li   x1, 16777416                      // (1 << 24) | 200 -- configured, resident
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x7, 3
    bne  x29, x7, done                     // no new trap
    li   x1, 16777416
    .insn i 0x0b, 0x5, x8, x1, 0
    li   x7, 3
    bne  x29, x7, done
    .insn r 0x5b, 0x0, 0x03, x23, x8, x0   // cgettag -- must be 1
    .insn r 0x5b, 0x0, 0x00, x9, x8, x0    // cgetbase
    la   x10, arena
    bne  x9, x10, done
    li   x24, 0x600D
    j    done
.balign 4
trap_handler:
    addi x29, x29, 1
    csrr x28, mtval
    csrr x5, mepc
    addi x5, x5, 4
    csrw mepc, x5
    mret
done:
1:
    j 1b
.section .data
.balign 64
arena:
    .space 64
