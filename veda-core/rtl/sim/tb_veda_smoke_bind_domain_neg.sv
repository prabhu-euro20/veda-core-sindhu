`timescale 1ns/1ps
// Per-object bind authority, ENFORCED -- the test the gate did not have.
//
// Everything in the policy-write test runs from boot, where no compartment is
// executing and the gate lets everything through by design. So the gate could
// have been deleted and the whole suite would still pass. This closes that.
//
// x22 -- from INSIDE a compartment, a narrowed object is refused with cause
//        0x0B and the destination comes back untagged
// x23 -- from the same place, an OPEN object still binds, so the gate is not
//        simply refusing everything
// x30 -- 0xD09E only if both held, in exactly one trap
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("refused=0x%0h mtval=0x%0h tag=%0d open-still-binds=%0d x30=0x%0h traps=%0d",
             dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[21],
             dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[25] == 64'hCB && dut.CPU_Xreg_val_a0[21] == 64'd0 &&
        dut.CPU_Xreg_val_a0[23] == 64'd1) begin
      $display("\n*** TEST PASSED *** (a compartment cannot bind a narrowed object, an open one still binds)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
