`timescale 1ns/1ps
// R43 -- Rebind must refresh an ALREADY-BOUND register: tagged, and naming this
// object. See veda_smoke_r43_rebind_identity.S.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (3000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R43 control 1, a genuine bind of A        : tag=%0d (must be 1)", dut.CPU_Xreg_val_a0[18]);
    $display("R43 control 2, rebinding the SAME object  : tag=%0d (must be 1 -- a genuine", dut.CPU_Xreg_val_a0[20]);
    $display("                                            refresh must still work)");
    $display("R43 THE FINDING 1, a DIFFERENT object     : tag=%0d (must be 0)", dut.CPU_Xreg_val_a0[22]);
    $display("R43 THE FINDING 2, an UNTAGGED destination: tag=%0d (must be 0)", dut.CPU_Xreg_val_a0[23]);
    $display("R43 control 3, a refusal is not corruption: tag=%0d (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("R43 all checks                            : x26=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[26]);
    if (dut.CPU_Xreg_val_a0[18] == 64'd1 && dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[22] == 64'd0 && dut.CPU_Xreg_val_a0[23] == 64'd0 &&
        dut.CPU_Xreg_val_a0[24] == 64'd1 && dut.CPU_Xreg_val_a0[26] == 64'h600D)
      $display("\n*** TEST PASSED *** (Rebind now refreshes only a register that is already bound to the object named, so an Offset meaningful in one object can no longer be carried onto another's bounds -- and the last untagged sealedness read in the machine is gone)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
