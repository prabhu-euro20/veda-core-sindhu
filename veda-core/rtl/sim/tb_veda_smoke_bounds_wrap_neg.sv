`timescale 1ns/1ps
// RTL-16 (R18): the bounds check must not wrap.
// x21 -- control: an ordinary in-bounds access still round-trips
// x22 -- offset -8 traps for BOTH load and store (the store is the dangerous one)
// x23 -- offset -16 traps, and so does the capability-width form
// x24 -- the object's own contents are untouched: no refused access half-applied
// x30 -- 0xD09E only if all held, in exactly four traps
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1200) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("ctrl=0x%0h wrap8=0x%0h wrap16=0x%0h intact=0x%0h x30=0x%0h traps=%0d mtval=0x%0h",
             dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
             dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20],
             dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd4 &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a wrapping offset can no longer reach outside the object, in either direction)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
