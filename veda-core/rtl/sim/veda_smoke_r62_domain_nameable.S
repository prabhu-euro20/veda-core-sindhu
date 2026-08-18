.section .text
.global _start
_start:
    // R62 (D6) -- veda.odt.set.domain wrote an unvalidated principal.
    //
    // The value came straight from rs2[19:0] into owner_domain with no check.
    // The refusal it needed was already in the same expression, one term to the
    // left: $veda_odt_valid refuses a policy on a slot that holds nothing,
    // because that would let software pre-stage rules on slots someone else has
    // yet to populate. The DOMAIN half is the stronger case -- a domain IS a
    // region (R10), so a policy naming an UNCONFIGURED region takes effect when
    // someone else is GIVEN that region. That is authority that OUTLIVES ITS
    // AUTHOR: an early-boot component with a delegated ODA can stamp a future
    // principal and then be dismissed, and dropping its ODA unstamps nothing.
    //
    // Region 3 is the fixture and it already exists: seeded
    // {rt_valid = 0, rt_resident = 1} by RTL-4 precisely so a check that reads
    // the wrong bit cannot pass. Naming it must be refused although it looks
    // resident.
    //
    // Object 130 is minted here; the fixtures seed 1, 2, 60, 104, 105, 106,
    // 108, 109, 257, 519 and 520, and nothing else.
    la   x30, trap_handler
    csrw mtvec, x30
    li   x29, 0
    li   x28, 0
    li   x20, 0
    li   x21, 0
    li   x22, 0
    li   x23, 0
    li   x24, 0

    la   x6, arena
    slli x6, x6, 32
    li   x7, 0x0020000C                     // Len 0x20, Perms Load|Store
    or   x2, x6, x7
    li   x1, 130
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2     // veda.odt.populate 130
    bne  x29, x0, done                      // the populate must not trap

    // CONTROL 1 -- a REAL principal is accepted. Without this a machine that
    // refused every set.domain would look identical to a machine that got it
    // right.
    li   x1, 130
    li   x4, 1                              // region 1: rt_valid, rt_resident
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    bne  x29, x0, done
    li   x20, 0x600D

    // CONTROL 2 -- so is the open sentinel. VEDA_DOMAIN_ANY is not a principal,
    // it is the ABSENCE of a restriction, and it is what Populate and Destroy
    // reset the field to -- gating it would have broken object destruction.
    li   x1, 130
    li   x4, 0xFFFFF
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    bne  x29, x0, done
    li   x21, 0x600D

    // THE FINDING -- region 3 has never been configured. rt_valid = 0 while
    // rt_resident = 1, so this also proves the check reads rt_valid and not the
    // residency bit beside it.
    li   x1, 130
    li   x4, 3
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x7, 1
    bne  x29, x7, done                      // exactly one trap
    li   x22, 0x600D

    // AND an out-of-window domain, which no region table entry can ever back.
    li   x1, 130
    li   x4, 0x3FF
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4
    li   x7, 2
    bne  x29, x7, done
    li   x23, 0x600D

    // CONTROL 3 -- a refused write wrote NOTHING. owner_domain still holds what
    // CONTROL 2 left there, so an ambient bind must still mint.
    li   x1, 130
    .insn i 0x0b, 0x5, x3, x1, 0            // veda.bind c3, 130
    li   x7, 2
    bne  x29, x7, done                      // no new trap
    .insn r 0x5b, 0x0, 0x03, x24, x3, x0    // cgettag x24, c3
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
