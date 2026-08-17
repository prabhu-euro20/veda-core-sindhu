`timescale 1ns/1ps
// RTL-8 (R12): the fail-closed half -- poison, and deny on an
// unreconstructible unwind. x30 = 0xD09E only if a handler that narrowed
// itself and then faulted was poisoned, the outer save survived, and the
// poisoned unwind DENIED (proven by a third trap occurring at all).
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1040) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("traps=%0d stage=%0d status@t2=0x%0h mepcc@t2=0x%0h x30=0x%0h",
              dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[24],
              dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[30]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd3)
      $display("\n*** TEST PASSED *** (poison set on a self-narrowed level, outer save intact, poisoned unwind denied)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
