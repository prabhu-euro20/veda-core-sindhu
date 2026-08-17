`timescale 1ns/1ps
// RTL-19: copy-on-write repaired end to end, with nothing hardcoded.
// x22 -- the faulting store ran AGAIN after the handler repaired the object,
//        and succeeded. mepc is deliberately not advanced: skipping it would
//        make the write the program asked for silently never happen.
// x23 -- the value really landed in memory
// x28 -- the handler discovered Object_ID 1 by ASKING the capability, not by
//        being told. Without cgetobjectid a handler knows only which REGISTER
//        faulted, never which object.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("setup=0x%0h retried=0x%0h landed=0x%0h discovered-oid=%0d x30=0x%0h traps=%0d",
             dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
             dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[28] == 64'd1 && dut.CPU_Xreg_val_a0[23] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (the handler found the faulting object itself, repaired it, and the store retried and succeeded)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
