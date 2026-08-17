`timescale 1ns/1ps
// R35 -- the veda_attr privilege term.
// x10 must equal the privileged write (0x0040_000C after the shift), proving the
//     register is writable at all -- without it a wired-shut CSR would pass.
// x11 must EQUAL x10, proving the unprivileged write did not land.
// x12 is the value the unprivileged write tried to install; the test fails if
//     x11 ever equals it, which is the escalation this closes.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (200) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("privileged write  x10=0x%0h (want 0x40000C)", dut.CPU_Xreg_val_a0[10]);
    $display("after droppriv    x11=0x%0h (must EQUAL x10 -- the write was refused)", dut.CPU_Xreg_val_a0[11]);
    $display("attempted value   x12=0x%0h (must NOT be what x11 reads)", dut.CPU_Xreg_val_a0[12]);
    $display("traps x20=%0d (want 0 -- a refused write is a silent no-op here, as with the four arms R27 gated)",
             dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h40000C &&
        dut.CPU_Xreg_val_a0[11] == dut.CPU_Xreg_val_a0[10] &&
        dut.CPU_Xreg_val_a0[11] != dut.CPU_Xreg_val_a0[12] &&
        dut.CPU_Xreg_val_a0[20] == 64'd0) begin
      $display("\n*** TEST PASSED *** (an unprivileged principal can no longer choose the Length and Perms that a later privileged Populate-Fast will mint into an object)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
