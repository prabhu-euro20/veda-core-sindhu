`timescale 1ns/1ps
// R63 -- a Populate could name a region that does not exist, and the descriptor
// landed in region 0's namespace. See veda_smoke_r63_region_write_alias.S.
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

    $display("R63 control 1 (empty slot refuses, cause 0x05) : x20=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[20]);
    $display("R63 THE FINDING (populate into region 5)       : x21=0x%0h (must be 0x600d -- refused;", dut.CPU_Xreg_val_a0[21]);
    $display("                                                 before the fix this populate was");
    $display("                                                 ACCEPTED and landed in region 0)");
    $display("R63 control 2 (the refusal wrote nothing)      : x22=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[22]);
    $display("R63 control 3 (a REAL region still populates)  : x24=0x%0h (must be 0x600d), tag=%0d (must be 1)",
             dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[23]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'd1    &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (the region half of an Object_ID is now an identity on the write path as well as the read path: a Populate naming an unconfigured region is refused, and a Populate naming a real one still works)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
