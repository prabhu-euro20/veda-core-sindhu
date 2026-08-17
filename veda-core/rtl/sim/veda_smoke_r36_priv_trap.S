.section .text
.global _start
// R36 -- WHAT HAPPENS TO PRIVILEGE ON A TRAP, AND WHO WROTE THE RULE.
//
// $priv has exactly ONE writer in this layer:
//     $priv = $reset ? 1'b1 : (>>1$is_veda_droppriv ? 1'b0 : >>1$priv);
// Set at reset, cleared once by veda.droppriv, never restored. The mux has NO
// arm for a trap and none for mret.
//
// Sail does the opposite: a trap sets cur_privilege = Machine, so the handler is
// privileged by construction. And Sail does not define veda.droppriv OR the
// custom-3 opcode at ALL -- zero mentions in the whole model.
//
// So TWENTY-THREE security gates on this layer -- R27's four CSR arms and the
// R35 veda_attr term among them -- rest on a bit whose only writer is an
// instruction the specification does not define, and whose value a trap cannot
// restore. This test measures the consequence rather than asserting it.
//
//   x10  populate BEFORE droppriv   -- 0x600D, the control: it works while privileged
//   x11  populate AFTER droppriv    -- must be refused
//   x12  did the trap handler regain privilege? probes it by trying a privileged
//        write from INSIDE the handler and reading it back
//   x20  traps
_start:
    la   x30, trap_handler
    csrw mtvec, x30
    li   x20, 0
    li   x12, 0

    // CONTROL: privileged populate works
    li   x1, 90
    li   x2, 0x80010C000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2
    li   x1, 90
    .insn i 0x0b, 0x5, x1, x1, 0          // bind c1, 90 -- succeeds only if the populate did
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  // cgettag c1 -- 1 while privileged

    .insn r 0x7b, 0x0, 0x00, x0, x0, x0   // veda.droppriv -- one way, no way back

    // Now unprivileged: a populate must be refused
    li   x1, 91
    li   x2, 0x80010D000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   // must trap
    li   x1, 91
    // c9, NOT c11. The first draft used c11 and read tag 1 -- because c11 is a
    // SEEDED FIXTURE and the suite runs with +veda_fixtures, so a FAILED bind
    // leaves the fixture's own tag standing and the test measures the fixture
    // instead of the bind. c9 is outside the fixture range on both layers,
    // which R24 established when it needed exactly this property.
    .insn i 0x0b, 0x5, x9, x1, 0          // bind c9, 91 -- the object should not exist
    .insn r 0x5b, 0x0, 0x03, x11, x9, x0  // cgettag c9 -- must be 0

1:  j 1b

trap_handler:
    addi x20, x20, 1
    // THE MEASUREMENT: inside the handler, is privilege restored? Try a write
    // that R27 gated on $priv and read it back. On Sail the handler is Machine
    // by construction; here the mux has no arm to make it so.
    li   x6, 0x1234
    csrw 0x7c2, x6                         // mepcc_base, gated on $priv by R27
    csrr x12, 0x7c2                        // 0x1234 if privileged, unchanged if not
    csrr x4, mepc
    addi x4, x4, 4
    csrw mepc, x4
    mret
