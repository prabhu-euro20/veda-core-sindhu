// D5 -- the CRBR saved shadow survives OCRETURN and is installed by the next
// unrelated mret. See veda_smoke_d5_crbr_shadow_leak.S for the finding.
`timescale 1ns/1ps
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

    $display("before entry           : region=%0d saved=0x%0h (must be 0 and 0xFFFFF)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[17]);
    $display("inside region 1        : region=%0d (must be 1)", dut.CPU_Xreg_val_a0[11]);
    $display("in trap handler        : region=%0d saved=%0d (must be 0 and 1 -- the shadow captured)",
             dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("after the OCRETURN exit: region=%0d saved=0x%0h (must be 0 and 0xFFFFF -- THE FINDING:",
             dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[18]);
    $display("                         before the fix saved read 1, because OCRETURN abandoned the");
    $display("                         trap frame and released everything in it EXCEPT the shadow)");
    $display("after an unrelated mret: region=%0d saved=0x%0h (must be 0 and 0xFFFFF -- THE CONSEQUENCE:",
             dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[22]);
    $display("                         before the fix region read 1 -- unrelated region-0 code resumed");
    $display("                         inside a compartment's region, and the current region is exempt");
    $display("                         from the residency check R55 put on veda.bind's minting path)");
    $display("completion sentinel    : x20=0x%0h (must be 0x600D), failure flag x21=0x%0h (must be 0)",
             dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[10] == 64'd0      &&
        dut.CPU_Xreg_val_a0[17] == 64'hFFFFF  &&
        dut.CPU_Xreg_val_a0[11] == 64'd1      &&
        dut.CPU_Xreg_val_a0[15] == 64'd0      &&
        dut.CPU_Xreg_val_a0[16] == 64'd1      &&
        dut.CPU_Xreg_val_a0[14] == 64'd0      &&
        dut.CPU_Xreg_val_a0[18] == 64'hFFFFF  &&
        dut.CPU_Xreg_val_a0[19] == 64'd0      &&
        dut.CPU_Xreg_val_a0[22] == 64'hFFFFF  &&
        dut.CPU_Xreg_val_a0[20] == 64'h600D   &&
        dut.CPU_Xreg_val_a0[21] == 64'd0) begin
      $display("\n*** TEST PASSED *** (OCRETURN now releases the CRBR saved shadow as well as the trap frame, so a handler left through a compartment crossing cannot strand a region for the next unrelated mret to install)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
