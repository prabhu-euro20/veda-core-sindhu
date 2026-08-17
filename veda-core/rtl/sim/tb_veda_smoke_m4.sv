`timescale 1ns/1ps
// Veda-Core RTL Milestone 4 smoke test: the full privileged lifecycle --
// ODT-Populate a fresh Object_ID, Bind/use it (OCS.D/OCL.D round-trip,
// CGetBase confirming the real populated fields), ODT-Destroy it, then
// two real negative checks that only make sense once Destroy is real:
// a post-destroy rebind against the same Object_ID (Tag must read 0)
// and a stale-generation re-check through the capability bound BEFORE
// the destroy (must be rejected, x11's sentinel must survive).
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (120) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x6(ocl old)=0x%0h x7(cgetbase)=0x%0h x10(c1 tag)=%0b x11(stale-ocl sentinel)=0x%0h",
              dut.CPU_Xreg_val_a0[6], dut.CPU_Xreg_val_a0[7],
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    // RTL-6: offsets corrected from the dead 16-byte layout (valid at +9,
    // generation at +8) to the real 32-byte one. Diagnostic only, not in
    // the pass condition. Entry 3 -> 3*32 = 96. This test DESTROYS
    // Object_ID=3, so resident is printed alongside valid: after RTL-6 a
    // destroyed slot must read both as 0.
    $display("odt_mem[Object_ID=3]: base=0x%0h valid=%0b resident=%0b gen=%0d",
              {dut.odt_mem[32'h9000_0000+32*3+3], dut.odt_mem[32'h9000_0000+32*3+2],
               dut.odt_mem[32'h9000_0000+32*3+1], dut.odt_mem[32'h9000_0000+32*3+0]},
              dut.odt_mem[32'h9000_0000+32*3+17][0],
              dut.odt_mem[32'h9000_0000+32*3+25][0],
              dut.odt_mem[32'h9000_0000+32*3+14]);

    // RTL-6: a destroyed slot must read valid=0 AND resident=0.
    //
    // This is a STRUCTURAL assertion on odt_mem, not an architectural one,
    // and the distinction is stated rather than blurred. Mutation testing
    // showed Destroy's residency-clearing write can be deleted with all 66
    // tests still passing, and that is not a gap in the tests -- it is
    // provable: every reader of `resident` is conjoined with `valid`
    // (Bind's gate is `valid && !resident`, and RTL-6c's page-out and
    // page-in gates both carry `valid` too), while Destroy sets valid=0.
    // So the residency byte of a dead slot is unobservable THROUGH THE
    // ISA by construction, and no behavioural test can reach it.
    //
    // It is asserted here anyway, directly against the array, because
    // "currently unreachable" is a statement about today's readers and not
    // about the field's meaning. DESIGN_02 has `cow` and `backing` still
    // to come; the first reader that consults residency without also
    // testing valid would inherit a stale true from every destroyed slot.
    // Pinning the invariant now costs one line and makes that future
    // change fail here instead of silently.
    if (dut.CPU_Xreg_val_a0[6] == 64'h1234567890ABCDEF &&
        dut.CPU_Xreg_val_a0[7] == 64'h80010200 &&
        dut.CPU_Xreg_val_a0[10] == 64'h0 &&
        dut.CPU_Xreg_val_a0[11] == 64'hDEAD &&
        dut.odt_mem[32'h9000_0000+32*3+17][0] == 1'b0 &&   // valid cleared
        dut.odt_mem[32'h9000_0000+32*3+25][0] == 1'b0) begin // resident too
      $display("\n*** TEST PASSED *** (ODT-Populate/Bind/use/Destroy lifecycle correct: fresh mint, real round-trip, post-destroy rebind Tag=0, stale-generation OCL rejected)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
