`timescale 1ns/1ps
// RTL mirror of Sail vc_cap_misaligned_neg: a 32-byte-misaligned OCS.C hard-traps
// with the new VEDA_CAUSE_CAP_MISALIGNED (0x08), in bounds, so the trap is the
// alignment rule and not a bounds violation.
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
    repeat (20) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("misaligned_neg: mcause=0x%0h mtval=0x%0h x20(not-reached marker)=0x%0h",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h18 &&   // E_Extension
        dut.CPU_Xreg_val_a0[11] == 64'h08 &&   // cap_idx 0, cause 0x08 misaligned
        dut.CPU_Xreg_val_a0[20] == 64'h0)      // the store did NOT fall through
      $display("\n*** TEST PASSED *** (misaligned OCS.C hard-traps with cause 0x08, in bounds)");
    else
      $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
