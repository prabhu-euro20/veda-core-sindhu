`timescale 1ns/1ps
// R36/R39 -- the privilege model. This testbench used to assert nothing, on
// purpose: it pinned the measured behaviour while the question was open. The
// question is answered, so it asserts the answer.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("privileged populate   x10=0x%0h (want 1 -- the control)", dut.CPU_Xreg_val_a0[10]);
    $display("unprivileged populate x11=0x%0h (want 0 -- refused)", dut.CPU_Xreg_val_a0[11]);
    $display("handler privileged?   x12=0x%0h (want 0x1234 -- a trap RAISES to Machine)",
             dut.CPU_Xreg_val_a0[12]);
    $display("U-mode CSR read       x15=0x%0h (want 0xBAD -- the read never executed)",
             dut.CPU_Xreg_val_a0[15]);
    $display("  ...and its cause    x17=0x%0h (want 0x600D -- mcause 0x02)",
             dut.CPU_Xreg_val_a0[17]);
    $display("ecall cause from U    x14=0x%0h (want 0x08 E_U_EnvCall, NOT 0x0B E_M_EnvCall)",
             dut.CPU_Xreg_val_a0[14]);
    $display("traps x20=%0d (want 4)", dut.CPU_Xreg_val_a0[20]);
    $display("live $priv = %0b (want 0 -- still User after the handler returned)", dut.CPU_priv_a0);
    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h0 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1234 &&
        dut.CPU_Xreg_val_a0[15] == 64'hBAD &&
        dut.CPU_Xreg_val_a0[17] == 64'h600D &&
        dut.CPU_Xreg_val_a0[14] == 64'h08 &&
        // Asserting the COUNT is what stops any single check passing for an
        // unrelated reason -- the first draft of this test read a seeded
        // fixture's tag and would have reported the opposite conclusion.
        dut.CPU_Xreg_val_a0[20] == 64'd4 &&
        dut.CPU_priv_a0 == 1'b0) begin
      $display("\n*** TEST PASSED *** (privilege is the specification's: software drops it with mstatus.MPP + mret, a trap raises to Machine so the handler can actually handle, mret returns to User, a Machine-only CSR is unreachable from User in BOTH directions, and ecall finally tells the handler who called)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
