`timescale 1ns/1ps
// R67 -- a callee the handler invoked must not consume the trap frame of the
// principal that trapped. See veda_smoke_r67_frame_owner.S.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (4000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R67 control, C's own PCC length      : 0x%0h (must be 0x40)", dut.CPU_Xreg_val_a0[19]);
    $display("R67 control, depth in the handler    : %0d (must be 1)", dut.CPU_Xreg_val_a0[20]);
    $display("R67 control, C's saved window        : 0x%0h (must be 0x40)", dut.CPU_Xreg_val_a0[24]);
    $display("R67 depth inside D, which never trapped : %0d (must be 1)", dut.CPU_Xreg_val_a0[21]);
    $display("R67 THE FINDING, depth after D returned : %0d (must be 1 -- D must not pop", dut.CPU_Xreg_val_a0[22]);
    $display("                                          a frame it did not push. Before");
    $display("                                          the fix this was 0)");
    $display("R67 C's saved window after D returned   : 0x%0h (must be 0x40 -- before the", dut.CPU_Xreg_val_a0[23]);
    $display("                                          fix 0xffffffffff, the frame gone)");
    $display("R67 all checks                          : x25=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[19] == 64'h40 && dut.CPU_Xreg_val_a0[20] == 64'd1 &&
        dut.CPU_Xreg_val_a0[24] == 64'h40 && dut.CPU_Xreg_val_a0[21] == 64'd1 &&
        dut.CPU_Xreg_val_a0[22] == 64'd1  && dut.CPU_Xreg_val_a0[23] == 64'h40 &&
        dut.CPU_Xreg_val_a0[25] == 64'h600D)
      $display("\n*** TEST PASSED *** (an OCRETURN that merely unwinds an OCInvoke the handler made no longer abandons the trap frame, so the principal that trapped keeps its right to be reinstated with its own bounds)");
    else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
