`timescale 1ns/1ps
// R68 -- Populate, Populate-Fast and Destroy must not authorize a delegated
// actor against a Base the object has left. See veda_smoke_r68_populate_stale.S.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (3000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R68 M-phase setup completed       : x18=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[18]);
    $display("R68 THE FINDING, User populate over the PAGED-OUT victim");
    $display("                                   : traps=%0d (must be 1 -- refused.", dut.CPU_Xreg_val_a0[19]);
    $display("                                     Before the fix 0, and the victim's");
    $display("                                     identity moved into attacker memory)");
    $display("R68 CONTROL, out-of-window object  : traps=%0d (must be 2 -- still refused)", dut.CPU_Xreg_val_a0[20]);
    $display("R68 all checks                     : x25=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[18] == 64'h600D && dut.CPU_Xreg_val_a0[19] == 64'd1 &&
        dut.CPU_Xreg_val_a0[20] == 64'd2   && dut.CPU_Xreg_val_a0[25] == 64'h600D)
      $display("\n*** TEST PASSED *** (a delegated actor can no longer mint over, or destroy, an object whose Base names a frame it has already left -- so inheriting a corpse no longer confers authority over the object that left it)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
