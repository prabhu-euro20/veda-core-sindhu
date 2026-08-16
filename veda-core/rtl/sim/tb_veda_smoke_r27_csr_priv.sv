`timescale 1ns/1ps
// R27: the four PCC/MEPCC CSRs must ignore an unprivileged write.
// This layer has no standard CSR privilege check, so before R27 the only
// protection was the forgeable "am I in a compartment" predicate (R26).
//  x10/x11/x12 = privileged read-back BEFORE droppriv
//  x13/x14/x15 = read-back AFTER an unprivileged write -- must be UNCHANGED
//  x16         = trap count, must be 0: a silent no-op, matching Sail, not a trap
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (400) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("before droppriv: pcc_len=0x%0h pcc_base=0x%0h mepcc_len=0x%0h",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12]);
    $display("after  unpriv w: pcc_len=0x%0h pcc_base=0x%0h mepcc_len=0x%0h   (must be IDENTICAL)",
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15]);
    $display("mepcc_base: before=0x%0h after=0x%0h  (must match)", dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[19]);
    $display("traps=%0d (want 0 -- a silent no-op, not a trap)", dut.CPU_Xreg_val_a0[16]);
    if (dut.CPU_Xreg_val_a0[13] == dut.CPU_Xreg_val_a0[10] &&
        dut.CPU_Xreg_val_a0[14] == dut.CPU_Xreg_val_a0[11] &&
        dut.CPU_Xreg_val_a0[15] == dut.CPU_Xreg_val_a0[12] &&
        dut.CPU_Xreg_val_a0[19] == dut.CPU_Xreg_val_a0[17] &&
        dut.CPU_Xreg_val_a0[16] == 64'd0) begin
      $display("\n*** TEST PASSED *** (unprivileged writes to veda_pcc_base, veda_pcc_length and veda_mepcc_length are silently ignored, so forging the compartment predicate is no longer enough on its own to rewrite one's own execution bounds)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
