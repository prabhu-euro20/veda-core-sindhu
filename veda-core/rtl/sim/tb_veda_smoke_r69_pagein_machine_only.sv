`timescale 1ns/1ps
// R69 -- page-in is Machine-only. See veda_smoke_r69_pagein_machine_only.S.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (4000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R69 M-phase setup                  : x18=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[18]);
    $display("R69 THE FINDING, delegated page.in : traps=%0d (must be 1 -- refused, even", dut.CPU_Xreg_val_a0[19]);
    $display("                                     with an ODA covering BOTH frames)");
    $display("R69 CONTROL, Machine's page.in     : traps=%0d (must be 2 -- the object is", dut.CPU_Xreg_val_a0[20]);
    $display("                                     NOT stranded)");
    $display("R69 it came back usable            : tag=%0d (must be 1)", dut.CPU_Xreg_val_a0[21]);
    $display("R69 all checks                     : x23=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[23]);
    if (dut.CPU_Xreg_val_a0[18] == 64'h600D && dut.CPU_Xreg_val_a0[19] == 64'd1 &&
        dut.CPU_Xreg_val_a0[20] == 64'd2   && dut.CPU_Xreg_val_a0[21] == 64'd1 &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D)
      $display("\n*** TEST PASSED *** (no delegated actor can restore a non-resident object, however wide its window, because the window can no longer stand proxy for having been the evictor -- and Machine can still restore it, so nothing is stranded)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
