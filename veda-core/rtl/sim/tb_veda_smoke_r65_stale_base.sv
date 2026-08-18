`timescale 1ns/1ps
// R65 -- a delegated actor may not authorize a policy write against a Base the
// object has left. See veda_smoke_r65_stale_base.S.
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
    repeat (4000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R65 M-phase setup completed        : x18=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[18]);
    $display("R65 THE FINDING, traps after the User set.domain on the PAGED-OUT victim");
    $display("                                   : x19=%0d (must be 1 -- refused. Before the fix 0)", dut.CPU_Xreg_val_a0[19]);
    $display("R65 CONTROL, out-of-window write   : x20=%0d (must be 2 -- still refused)", dut.CPU_Xreg_val_a0[20]);
    $display("R65 page.in added no trap          : x21=%0d (must be 3)", dut.CPU_Xreg_val_a0[21]);
    $display("R65 the object moved to new_frame  : x24=%0d (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("R65 all checks                     : x25=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[18] == 64'h600D && dut.CPU_Xreg_val_a0[19] == 64'd1 &&
        dut.CPU_Xreg_val_a0[20] == 64'd2   && dut.CPU_Xreg_val_a0[21] == 64'd3 &&
        dut.CPU_Xreg_val_a0[24] == 64'd1   && dut.CPU_Xreg_val_a0[25] == 64'h600D)
      $display("\n*** TEST PASSED *** (a delegated actor can no longer write policy on an object whose Base describes a frame it has already left, so authority over a reclaimed frame no longer follows the object to wherever the pager restores it)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
