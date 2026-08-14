`timescale 1ns/1ps
// RTL-17: the ODT policy write path.
// x21 -- an ordinary bind and round-trip still work
// x22 -- THE POINT: after narrowing the object, the SAME capability still loads
//        AND stores, and still sees the value written before the narrowing.
//        A bumped generation would trap 0x02 here instead.
// x23 -- boot is in no compartment, so it may still bind a narrowed object
// x24 -- widening back to ANY works, so the field is genuinely being read
// x30 -- 0xD09E only if all held, with ZERO traps
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (300) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("bind=0x%0h narrowed-still-works=0x%0h boot=0x%0h widen=0x%0h x30=0x%0h traps=%0d mtval=0x%0h",
             dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
             dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20],
             dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd0 &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D && dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (policy can be changed without killing the capabilities that describe it)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
