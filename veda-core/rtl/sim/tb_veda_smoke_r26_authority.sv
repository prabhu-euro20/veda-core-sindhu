`timescale 1ns/1ps
// R26 -- AUTHORITY IS A NAME, NOT A BOUND.
//
// Six security gates asked "does this code hold machine authority?" by testing
// veda_pcc_length == VEDA_PCC_UNBOUNDED. Length is a NUMBER SOFTWARE CHOOSES:
// enter a compartment on a code object whose Length IS the sentinel and every
// one of those gates reads true at once, so the compartment can rewrite its own
// execution bounds and redirect every future trap. The fix asks the PCC's
// OBJECT instead -- VEDA_OBJECT_NONE is structurally unreachable, since no
// capability bearing that name can cross a domain boundary in the first place.
//
// SINGLE-TERM DISCRIMINATOR, and this is the entire point of the test.
// Assertion 3 pins veda_pcc_length INSIDE the compartment at 0xFFFFFFFFFF --
// byte-identical to its value at boot. The length term therefore reads the SAME
// in both halves of this test and CANNOT be what refuses. Only the object
// differs: NONE outside, 30 inside. Without that pin the test would still pass
// if the compartment had merely narrowed its own bounds, which proves nothing
// about R26.
//
// Assertion 2 is the other half and is equally load-bearing: OUTSIDE, the same
// write must LAND. A test where the write is refused everywhere would pass with
// the CSR simply wired shut.
//
// Assertion 1 exists because an earlier draft of this test FELL THROUGH: the
// OCInvoke trapped, the handler stepped over it, and execution entered the
// compartment label in a straight line while never entering the compartment.
// Every "inside" check would then have been evaluated outside. Pinning
// pcc_object == 30 is what makes entry a fact rather than an assumption.
//
// 0x7C3 (mepcc_length) rather than 0x7C1: writing a small value to 0x7C1
// narrows the PCC of the code CURRENTLY EXECUTING, so the next fetch is out of
// bounds and the machine trap-loops. 0x7C3 sits on the same gate and is the
// trap-RETURN forge, so it is the more security-relevant of the two anyway.
//
// TWO REFUSALS, RECORDED SEPARATELY. Both must hold: closing the bounds forge
// and not the vector capture still leaves the compartment able to take every
// future fault. Each cause goes to its own register rather than a shared one,
// so neither refusal can go unmeasured.
//
// Both causes are 0x02, ILLEGAL INSTRUCTION, not the Veda trap 0x18 -- MEASURED,
// after an earlier draft of this header asserted 0x18 for the mepcc write and
// was simply wrong. $veda_csr_escape_violation feeds $veda_illegal_instr
// (veda_core.tlv:4251), so a CSR this context may not write is refused the way
// RISC-V refuses any inaccessible CSR. That agrees with the Sail layer, which
// gates mtvec in the CSR access predicate and returns Err(()) from the
// 0x7C0-0x7C3 writes -- both of which surface as illegal instruction as well.
//
// THE MUTANT, and this is what makes the test a proof rather than a green light.
// Delete R26's single pcc_object comparator from $veda_csr_escape_violation and
// re-run: traps 0, mepcc_length 0x40 -- the compartment rewrote its own
// execution bounds -- and mtvec 0x800000FC, the hijacked vector. The escape is
// (R50 increment 2 shifted trap_handler by 12 bytes: the retain-mask write is
//  two instructions ahead of the crossing. The hard-coded address is updated
//  rather than the test relaxed -- it is pinning a REAL address, and that is
//  the point of the assertion.)
// real, this test fails on the unfixed design, and it fails in exactly the way
// the finding predicted rather than merely somewhere.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (2800) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end

    $display("crossing reached x18=0x%0h (want 0xA11E)   traps=%0d (want 2)",
             dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[20]);
    $display("INSIDE  pcc_object=0x%0h (want 0x1E -- entry is a fact, not an assumption)",
             dut.CPU_veda_pcc_object_a0);
    $display("INSIDE  pcc_length=0x%0h (want 0xFFFFFFFFFF -- IDENTICAL to boot; the length term cannot be what refuses)",
             dut.CPU_veda_pcc_length_a0);
    $display("OUTSIDE mepcc write x10=0x%0h (want 0x40 -- it LANDS, so the gate really is open out there)",
             dut.CPU_Xreg_val_a0[10]);
    $display("        restored    x21=0x%0h (want 0xFFFFFFFFFF)", dut.CPU_Xreg_val_a0[21]);
    $display("INSIDE  mepcc write x11=0x%0h (want 0xFFFFFFFFFF -- REFUSED, the write never landed)",
             dut.CPU_Xreg_val_a0[11]);
    $display("INSIDE  mtvec write x12=0x%0h (want 0x80000114 trap_handler, NOT 0x800000FC hijacked)",
             dut.CPU_Xreg_val_a0[12]);
    $display("        hijacked    x14=0x%0h (want 0 -- never executed)   reached end x15=0x%0h (want 0x600D)",
             dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15]);
    $display("        causes      mepcc=0x%0h mtvec=0x%0h (want 0x2/0x2 -- illegal instruction, measured not assumed)",
             dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[18] == 64'hA11E             &&
        dut.CPU_veda_pcc_object_a0 == 44'h1E            &&
        dut.CPU_veda_pcc_length_a0 == 40'hFFFFFFFFFF    &&
        dut.CPU_Xreg_val_a0[10] == 64'h40               &&
        dut.CPU_Xreg_val_a0[21] == 64'hFFFFFFFFFF       &&
        dut.CPU_Xreg_val_a0[11] == 64'hFFFFFFFFFF       &&
        dut.CPU_Xreg_val_a0[12] == 64'h80000114         &&
        dut.CPU_Xreg_val_a0[14] == 64'h0                &&
        dut.CPU_Xreg_val_a0[15] == 64'h600D             &&
        dut.CPU_Xreg_val_a0[23] == 64'h2                &&
        dut.CPU_Xreg_val_a0[24] == 64'h2                &&
        dut.CPU_Xreg_val_a0[20] == 64'd2) begin
      $display("\n*** TEST PASSED *** (a compartment entered on a sentinel-Length code object holds a PCC whose Length is byte-identical to the machine's at boot, and is still refused both the execution-bounds forge and the trap-vector capture -- authority now follows the name, which cannot be chosen, rather than a bound, which can)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
