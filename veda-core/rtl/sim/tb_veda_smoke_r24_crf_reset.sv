`timescale 1ns/1ps
// R24 -- the capability register file's architectural reset state.
// x10 cgettype c9 at reset : 0xFFFF -- UNSEALED, and NOT 0, which is a real
//   seal type CSeal can mint from an authority whose Offset is zero
// x11 cgettag  c9 at reset : 0
// x12 tag  after rebind c9 : 1        <- the discriminator: rebind into a
// x13 base after rebind c9 : 0x80010900   never-written register must SUCCEED,
// x14 len  after rebind c9 : 0x40         and only the reset otype can refuse it
// x15 tag  after cseal  c8 : 1        <- control: sealing keeps the tag
// x16 tag  after rebind c8 : 0        <- control: rebind onto a genuinely
//   sealed register soft-fails. Without x15/x16 this test would still pass with
//   the sealed term deleted outright, and would be measuring only "rebind works".
// x20 traps                : 0
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (400) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("reset  otype x10=0x%0h (want 0xFFFF)   tag x11=0x%0h (want 0)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("rebind c9    tag x12=0x%0h (want 1)  base x13=0x%0h (want 0x80010900)  len x14=0x%0h (want 0x40)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14]);
    $display("sealed c8    tag x15=0x%0h (want 1)   after rebind x16=0x%0h (want 0 -- soft-fail)",
             dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("traps x20=%0d (want 0)", dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[10] == 64'hFFFF      &&
        dut.CPU_Xreg_val_a0[11] == 64'h0         &&
        dut.CPU_Xreg_val_a0[12] == 64'h1         &&
        dut.CPU_Xreg_val_a0[13] == 64'h80010900  &&
        dut.CPU_Xreg_val_a0[14] == 64'h40        &&
        dut.CPU_Xreg_val_a0[15] == 64'h1         &&
        dut.CPU_Xreg_val_a0[16] == 64'h0         &&
        dut.CPU_Xreg_val_a0[20] == 64'd0) begin
      $display("\n*** TEST PASSED *** (an untouched capability register reads UNSEALED rather than sealed-with-type-zero, so Rebind into it succeeds -- and Rebind onto a genuinely sealed register still soft-fails)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
