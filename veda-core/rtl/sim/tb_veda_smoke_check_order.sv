`timescale 1ns/1ps
// R19 increment 1 -- the ORDER of the dereference cause chain.
// mtval is {cap_idx:5, cause:5}.
//
// x10 P1 ocs      : Length-0 capability store -> 0x41 = c2<<5 | BOUNDS 0x01
// x11 P2 ocsc     : out-of-bounds OCS.C       -> 0x21 = c1<<5 | BOUNDS 0x01
// x12 P3 nmc_add.d: Length-0 cap (offset comes from the CAPABILITY, not rs2) -> 0x81 = c4<<5 | 0x01
// x13 P4 nmc_add.w: same                                       -> 0x81
// x14 P5 atomic   : same                                       -> 0x81
//   all five would have reported 0x0C under the old order, arming a copy for an
//   access that was refused anyway. Five separate chains, one phase each,
//   because an edit applied to four of five has slipped through twice here.
// x15 P6 residency: non-resident cow object   -> 0x16A = c11<<5 | RESIDENCY 0x0A
//   NOT 0x0C: you cannot copy an object that is not in memory.
// x16 P7 control  : in-bounds resident cow    -> 0x2C = c1<<5 | COW 0x0C
//   without this, every phase above would also pass if the cow arm were deleted.
// x17 P8 the gate : capability bound AFTER cow, so it lacks store, must STILL
//   report 0x0C and never 0x13                -> 0x6C = c3<<5 | COW 0x0C
// x20 total traps : exactly 8
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (800) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("P1 ocs   =0x%0h (want 0x41)   P2 ocsc  =0x%0h (want 0x21)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("P3 nmc.d =0x%0h (want 0x81)   P4 nmc.w =0x%0h (want 0x81)   P5 atomic=0x%0h (want 0x81)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14]);
    $display("P6 resid =0x%0h (want 0x16A -- residency, NOT cow)", dut.CPU_Xreg_val_a0[15]);
    $display("P7 ctrl  =0x%0h (want 0x2C  -- cow still fires)     P8 gate =0x%0h (want 0x6C, NOT 0x13)",
             dut.CPU_Xreg_val_a0[16], dut.CPU_Xreg_val_a0[17]);
    $display("traps=%0d (want 8)   last mcause=0x%0h (want 0x18)",
             dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h41  &&
        dut.CPU_Xreg_val_a0[11] == 64'h21  &&
        dut.CPU_Xreg_val_a0[12] == 64'h81  &&
        dut.CPU_Xreg_val_a0[13] == 64'h81  &&
        dut.CPU_Xreg_val_a0[14] == 64'h81  &&
        dut.CPU_Xreg_val_a0[15] == 64'h16A &&
        dut.CPU_Xreg_val_a0[16] == 64'h2C  &&
        dut.CPU_Xreg_val_a0[17] == 64'h6C  &&
        dut.CPU_Xreg_val_a0[20] == 64'd8   &&
        dut.CPU_Xreg_val_a0[21] == 64'h18) begin
      $display("\n*** TEST PASSED *** (every refusal now precedes every repair, on all five cow-bearing chains; residency outranks copy-on-write; the cow arm still fires in bounds; and the gated permission arm keeps copy-on-write reachable for a capability that lacks store by construction)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
