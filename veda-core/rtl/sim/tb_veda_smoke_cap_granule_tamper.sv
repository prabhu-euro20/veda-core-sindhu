`timescale 1ns/1ps
// RTL mirror of Sail vc_cap_granule_tamper_neg: an ordinary store into byte 16
// of a stored capability must destroy its tag (32-byte granule).
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
    repeat (18) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("granule_tamper: roundtrip_tag=%0b after_tamper_tag=%0b",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h1 && dut.CPU_Xreg_val_a0[11] == 64'h0)
      $display("\n*** TEST PASSED *** (a plain store into byte 16 destroys the stored capability's tag)");
    else
      $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
