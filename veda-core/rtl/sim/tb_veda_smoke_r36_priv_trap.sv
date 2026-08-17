`timescale 1ns/1ps
// R36 -- privilege on a trap. This testbench does not assert a "correct" answer,
// because which answer is correct is exactly the open question. It PINS the
// measured behaviour so the divergence is recorded and cannot drift unnoticed
// while the two layers are reconciled.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (400) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("privileged populate  x10=0x%0h (want 1 -- the control)", dut.CPU_Xreg_val_a0[10]);
    $display("unprivileged populate x11=0x%0h (want 0 -- refused)", dut.CPU_Xreg_val_a0[11]);
    $display("handler privileged?  x12=0x%0h (0x1234 = trap RESTORED privilege, 0 = it did NOT)",
             dut.CPU_Xreg_val_a0[12]);
    $display("traps x20=%0d", dut.CPU_Xreg_val_a0[20]);
    $display("live $priv = %0b", dut.CPU_priv_a0);
    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h0 &&
        dut.CPU_Xreg_val_a0[12] == 64'h0 &&
        // Two refusals: the unprivileged populate, and the bind that then finds
        // no object. Asserting the COUNT is what stops the tag check passing for
        // some unrelated reason -- the first draft of this test read a seeded
        // fixture's tag and would have reported the opposite conclusion.
        dut.CPU_Xreg_val_a0[20] == 64'd2 &&
        dut.CPU_priv_a0 == 1'b0) begin
      $display("\n*** TEST PASSED *** (measured and pinned: veda.droppriv is one-way and a trap does NOT restore privilege on this layer, so a handler entered after a drop cannot perform any of the 23 privileged operations -- Sail raises to Machine on every trap and does not define this instruction at all)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
