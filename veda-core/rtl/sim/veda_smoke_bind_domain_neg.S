
.section .text
.global _start
// PER-OBJECT BIND AUTHORITY, ENFORCED -- the test the gate did not have.
//
// vc_odt_set_domain.S proves the policy field can be written without killing
// capabilities. It does NOT prove the field is enforced, because everything it
// does runs from boot, where no compartment is executing and the gate lets
// everything through by design.
//
// So the gate could have been deleted entirely and the whole corpus would still
// pass. That is exactly the shape of hole this session has found three times:
// a mechanism present, believed, and never exercised on the path that matters.
//
//   1. narrow object 2 to domain 7, from boot
//   2. enter a compartment whose code object lives in region 0
//   3. from inside, bind object 2 -- domain 0 is not domain 7, so it must TRAP
//      with cause 0x0B, and the destination capability must come back untagged
//   4. from the same place, bind an object left OPEN -- must still succeed, or
//      the gate is simply refusing everything and step 3 proves nothing
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    li   x20, 0

    // ---- narrow object 2 to domain 7, while still in no compartment
    li   x1, 2
    li   x4, 7
    .insn r 0x0b, 0x1, 0x06, x5, x1, x4   # veda.odt.set.domain 2 -> 7
    bne  x20, x0, fail

    // ---- build a region-0 compartment: code, handoff data, type authority
    li   x6, 0xFFFFFFFFFF
    slli x6, x6, 16
    ori  x6, x6, 0x0402                   // UNBOUNDED, Execute|Invoke
    csrw 0x7C4, x6
    la   x7, compartment
    li   x1, 210
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7   # populate.fast -- CODE
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0400
    csrw 0x7C4, x6
    la   x7, data_pad
    li   x1, 211
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7
    li   x6, 0x100
    slli x6, x6, 16
    ori  x6, x6, 0x0300
    csrw 0x7C4, x6
    la   x7, auth_pad
    li   x1, 212
    .insn r 0x0b, 0x0, 0x04, x5, x1, x7

    li   x1, 210
    .insn i 0x0b, 0x5, x0, x1, 0          // bind c0, code
    li   x1, 211
    .insn i 0x0b, 0x5, x1, x1, 0          // bind c1, data
    li   x1, 212
    .insn i 0x0b, 0x5, x2, x1, 0          // bind c2, authority
    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke -- ENTER
    j    fail

.balign 4
compartment:
    // PCC now names object 210, so the executing domain is region 0.

    // ---- the narrowed object must be refused
    li   x1, 2
    // c6, not c10: capability registers 10, 11 and 13 are RESET-SEEDED in this
    // model (and 11-14 in the RTL), so a refused bind leaves the seeded value --
    // correctly, since a refusal must not touch the destination -- and cgettag
    // then reads 1 for reasons that have nothing to do with this test. c5-c9 are
    // free on both layers.
    .insn i 0x0b, 0x5, x6, x1, 0          // veda.bind c6, 2 -- must TRAP
    li   x6, 1
    bne  x20, x6, fail
    li   x6, 0xCB                         // (cap_idx 6 << 5) | 0x0B
    bne  x25, x6, fail
    .insn r 0x5b, 0x0, 0x03, x21, x6, x0  # cgettag -- must be 0
    bnez x21, fail
    li   x22, 0x600D

    // ---- an OPEN object from the same place must still bind
    li   x1, 211
    .insn i 0x0b, 0x5, x7, x1, 0          // veda.bind c7, 211 -- must SUCCEED
    li   x6, 1
    bne  x20, x6, fail                    // still exactly one trap
    .insn r 0x5b, 0x0, 0x03, x23, x7, x0
    li   x6, 1
    bne  x23, x6, fail

    li   x6, 0x600D
    bne  x22, x6, fail
    li   x30, 0xD09E
    j    done

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr x25, mtval
    addi x20, x20, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    li   x30, 0xBAD

.section .data
.balign 32
data_pad:
    .zero 0x100
.balign 32
auth_pad:
    .zero 0x100

done:
    j    done
