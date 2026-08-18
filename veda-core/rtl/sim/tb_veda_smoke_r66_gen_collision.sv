`timescale 1ns/1ps
// R66 -- a Populate that cannot deliver a fresh generation must be refused.
// See veda_smoke_r66_gen_collision.S.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (3000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R66 control 1, populate #1 accepted   : traps=%0d (must be 0 -- 0xFFFFFE to", dut.CPU_Xreg_val_a0[18]);
    $display("                                        0xFFFFFF is a legal increment)");
    $display("R66 control 2, the bind minted        : tag=%0d (must be 1)", dut.CPU_Xreg_val_a0[19]);
    $display("R66 THE FINDING, populate #2          : traps=%0d (must be 1 -- refused.", dut.CPU_Xreg_val_a0[21]);
    $display("                                        Before the fix 0, and two incarnations");
    $display("                                        then shared one generation)");
    $display("R66 the old capability still reads    : 0x%0h (must be 0xabcd -- the refusal", dut.CPU_Xreg_val_a0[10]);
    $display("                                        changed nothing)");
    $display("R66 all checks                        : x23=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[23]);
    if (dut.CPU_Xreg_val_a0[18] == 64'd0 && dut.CPU_Xreg_val_a0[19] == 64'd1 &&
        dut.CPU_Xreg_val_a0[21] == 64'd1 && dut.CPU_Xreg_val_a0[10] == 64'hABCD &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D)
      $display("\n*** TEST PASSED *** (the slot is now retired at the moment it would need a generation bump it cannot deliver, rather than one Populate later -- so no two incarnations can share a generation while the first one's capabilities are live)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
