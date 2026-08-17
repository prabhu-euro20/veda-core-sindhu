`timescale 1ns/1ps
// TEMPORAL SAFETY -- use-after-free on every dereference path.
// The census found $veda_gen_stale unverified on SIX of seven chains: delete it
// and a stale capability reads and writes freed memory with no trap, and all 82
// tests stay green. Each phase frees an object and RE-POPULATES the same slot,
// so the stale capability is tagged, unsealed, permitted, in bounds and
// resident -- only its generation differs, and nothing but $veda_gen_stale can
// refuse it.
// mtval = {cap_idx:5, cause:5}; c1 with cause 0x02 = 0x22 on every phase.
//   x10 ocs.d   x11 ocl.d   x12 ocs.c   x13 ocl.c   x14 nmc.d   x15 nmc.w
//   x16 control read-back through a FRESH bind, must be 0x600D
//   x17 trap count at the control, must be 6 (the control must not trap)
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (3600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("stale mtval -- ocs.d=0x%0h ocl.d=0x%0h ocs.c=0x%0h ocl.c=0x%0h nmc.d=0x%0h nmc.w=0x%0h  (all want 0x22)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12],
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15]);
    $display("control -- fresh bind read-back=0x%0h (want 0x600D)   traps=%0d (want 6)",
             dut.CPU_Xreg_val_a0[16], dut.CPU_Xreg_val_a0[17]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h22 && dut.CPU_Xreg_val_a0[11] == 64'h22 &&
        dut.CPU_Xreg_val_a0[12] == 64'h22 && dut.CPU_Xreg_val_a0[13] == 64'h22 &&
        dut.CPU_Xreg_val_a0[14] == 64'h22 && dut.CPU_Xreg_val_a0[15] == 64'h22 &&
        dut.CPU_Xreg_val_a0[16] == 64'h600D && dut.CPU_Xreg_val_a0[17] == 64'd6) begin
      $display("\n*** TEST PASSED *** (a capability to a freed-and-reused object is refused on all six dereference paths with cause 0x02, while a fresh bind to the same object still works -- so the refusal is the generation, not the object)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
