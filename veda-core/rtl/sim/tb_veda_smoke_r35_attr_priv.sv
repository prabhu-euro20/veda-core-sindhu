`timescale 1ns/1ps
// R35/R39 -- the veda_attr privilege term, now a real refusal on both layers.
// x10 must equal the privileged write (0x0040_000C after the shift), proving the
//     register is writable at all -- without it a wired-shut CSR would pass.
// x11 must stay 0xBAD: the unprivileged READ is refused too, not just the write.
// x13 is the privileged read-back -- must EQUAL x10 and must NEVER equal x12.
// x20 must be 3: the refused write, the refused read, and the ecall.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (400) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("privileged write   x10=0x%0h (want 0x40000C)", dut.CPU_Xreg_val_a0[10]);
    $display("unprivileged read  x11=0x%0h (want 0xBAD -- it never executed)", dut.CPU_Xreg_val_a0[11]);
    $display("attempted value    x12=0x%0h (must NOT be what x13 reads)", dut.CPU_Xreg_val_a0[12]);
    $display("privileged readback x13=0x%0h (must EQUAL x10 -- the write was refused)", dut.CPU_Xreg_val_a0[13]);
    $display("traps x20=%0d (want 3 -- refused write, refused read, ecall)", dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h40000C &&
        dut.CPU_Xreg_val_a0[11] == 64'hBAD &&
        dut.CPU_Xreg_val_a0[13] == dut.CPU_Xreg_val_a0[10] &&
        dut.CPU_Xreg_val_a0[13] != dut.CPU_Xreg_val_a0[12] &&
        dut.CPU_Xreg_val_a0[20] == 64'd3) begin
      $display("\n*** TEST PASSED *** (an unprivileged principal can no longer choose the Length and Perms that a later privileged Populate-Fast will mint into an object -- and can no longer read them either, since check_CSR_priv gates the access, not the write)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
