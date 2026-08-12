`timescale 1ns/1ps
// RTL-2b: every field of a capability must survive the 256-bit memory round-trip
// exactly. A one-position error anywhere in the pack/unpack layout corrupts at
// least one field, which zero-regression testing would not catch.
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
    repeat (22) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("cap256 before: base=0x%0h len=0x%0h perm=0x%0h type=0x%0h off=0x%0h",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12],
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14]);
    $display("cap256 after : base=0x%0h len=0x%0h perm=0x%0h type=0x%0h off=0x%0h tag=%0b",
             dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16], dut.CPU_Xreg_val_a0[17],
             dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[15] == dut.CPU_Xreg_val_a0[10] &&   // Base survived
        dut.CPU_Xreg_val_a0[16] == dut.CPU_Xreg_val_a0[11] &&   // Length survived
        dut.CPU_Xreg_val_a0[17] == dut.CPU_Xreg_val_a0[12] &&   // Perms survived
        dut.CPU_Xreg_val_a0[18] == dut.CPU_Xreg_val_a0[13] &&   // otype survived
        dut.CPU_Xreg_val_a0[19] == dut.CPU_Xreg_val_a0[14] &&   // Offset survived
        dut.CPU_Xreg_val_a0[14] == 64'h18 &&                    // and it really was nonzero
        dut.CPU_Xreg_val_a0[20] == 64'h1)                       // still tagged
      $display("\n*** TEST PASSED *** (all fields exact across the 256-bit memory round-trip)");
    else
      $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
