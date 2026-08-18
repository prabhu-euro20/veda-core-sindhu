`timescale 1ns/1ps
// R62 (D6) -- veda.odt.set.domain wrote an unvalidated principal. A policy
// naming an unconfigured region is authority that outlives its author. See
// veda_smoke_r62_domain_nameable.S.
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
    repeat (3000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("R62 control 1 (a real principal is accepted) : x20=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[20]);
    $display("R62 control 2 (the open sentinel is accepted): x21=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[21]);
    $display("R62 THE FINDING (region 3, rt_valid=0)       : x22=0x%0h (must be 0x600d -- refused,", dut.CPU_Xreg_val_a0[22]);
    $display("                                               and refused on rt_valid, not on the");
    $display("                                               rt_resident=1 bit beside it)");
    $display("R62 out-of-window domain 0x3FF               : x23=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[23]);
    $display("R62 control 3 (a refused write wrote nothing): x24=0x%0h (must be 1 -- the ambient", dut.CPU_Xreg_val_a0[24]);
    $display("                                               bind still mints, so owner_domain is");
    $display("                                               still ANY and not 3)");

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'd1) begin
      $display("\n*** TEST PASSED *** (a domain must be a principal that exists: set.domain now refuses an unconfigured region, so no actor can stamp an object for a principal that has not been created yet and then be dismissed)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
