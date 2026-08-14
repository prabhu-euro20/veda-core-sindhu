`timescale 1ns/1ps
// RTL-18: copy-on-write.
// x22 -- the capability minted BEFORE the object became cow still faults, with
//        cause 0x0C rather than the store-permission 0x13. This is the one that
//        matters: at fork() the parent holds exactly such a capability and it is
//        the first that will be written.
// x23 -- reads still work while shared, and the refused store never landed
// x24 -- re-binding does NOT hand store permission back (the attenuation lives
//        in Bind, so no re-derivation escapes it)
// x26 -- NMC_ADD, a second write path, faults on the same object
// x27 -- clearing the bit restores writes, so the field is live
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (400) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("setup=0x%0h cowfault=0x%0h reads=0x%0h rebind=0x%0h nmc=0x%0h cleared=0x%0h x30=0x%0h traps=%0d mtval=0x%0h",
             dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
             dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[27],
             dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[25]);
    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E && dut.CPU_Xreg_val_a0[20] == 64'd2 &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D && dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (copy-on-write: a pre-existing capability still faults, re-binding cannot escape, and both write paths are covered)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
