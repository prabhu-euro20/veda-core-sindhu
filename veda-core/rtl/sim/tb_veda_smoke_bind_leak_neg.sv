`timescale 1ns/1ps
// RTL-14: a failed Bind must hand back nothing.
// x21/x22 -- positive control: a real bind still returns tag=1 and a real Base
// x24     -- THE LEAK: cgetbase after a silently-failed probe. Must be 0.
// x30     -- 0xD09E only if the probe leaked nothing at all
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (200) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("ctrl tag=%0d base=0x%0h | probe tag=%0d base=0x%0h len=0x%0h perm=0x%0h | notfound base=0x%0h | x30=0x%0h",
             dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
             dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[26],
             dut.CPU_Xreg_val_a0[27], dut.CPU_Xreg_val_a0[30]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[22] != 64'h0 &&
        dut.CPU_Xreg_val_a0[24] == 64'h0) begin
      $display("\n*** TEST PASSED *** (a silently-failed bind leaks no Base, Length or Perms, while a real bind still works)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
