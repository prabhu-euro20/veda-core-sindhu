`timescale 1ns/1ps
// R48 -- the ODA is cleared at every compartment crossing.
//
// OCInvoke narrows PCC, installs a fresh IDC, reloads the CRBR and clears the
// SSC. It left veda_oda untouched, and the argument against that was already
// written down for the SSC inside the OCInvoke clause itself. Pre-R47 the point
// was moot (an unscoped ODA reached all of memory from anywhere); R47 gave the
// ODA a window, so inheriting it is inheriting mint authority over the caller's
// memory. Measured on Sail before the fix: a User compartment holding nothing
// but a code and a data capability destroyed the caller's object and minted a
// fresh descriptor over the caller's window, ZERO traps.
//
// This lives here rather than in the differential harness because that harness
// runs with test_fixtures FALSE (R24), the region table has no software write
// path at all, and OCInvoke requires an RT-resident region -- see
// difftest/blocked/p21_oda_crossing.S and DESIGN_07 R51.
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

    repeat (4000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    // CONTROL 0 is checked FIRST and it is checked at all, because every other
    // assertion here is a refusal assertion: a core on which the delegated ODA
    // never worked at User would satisfy all of them for entirely the wrong
    // reason. This project has found that shape six times.
    $display("R48 control 0 (pre-crossing delegated mint): x20=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[20]);
    $display("R48 callee's ODT-Populate cause           : x21=0x%0h (must be 0x2)",     dut.CPU_Xreg_val_a0[21]);
    $display("R48 control 1 (callee still works via IDC): x22=0x%0h (must be 0x5a5a)",  dut.CPU_Xreg_val_a0[22]);
    $display("R48 nothing was minted                    : x23=0x%0h (must be 0x0)",     dut.CPU_Xreg_val_a0[23]);
    $display("R48 caller's own earlier mint survived    : x24=0x%0h (must be 0x1)",     dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D &&
        dut.CPU_Xreg_val_a0[21] == 64'h2    &&
        dut.CPU_Xreg_val_a0[22] == 64'h5A5A &&
        dut.CPU_Xreg_val_a0[23] == 64'h0    &&
        dut.CPU_Xreg_val_a0[24] == 64'h1) begin
      $display("\n*** TEST PASSED *** (the ODA is cleared at the compartment crossing: the callee's ODT-Populate over the caller's window is refused and MINTS NOTHING, while the callee's own legitimate IDC access and the caller's own pre-crossing mint are both untouched)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
