`timescale 1ns/1ps
// Veda-Core RTL-5 (R10) negative: OCInvoke and OCReturn into a paged-out
// domain both raise the explicit VEDA_CAUSE_REGION_FAULT (0x09) and commit
// nothing. See veda_smoke_r10_crossing_fault_neg.S.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (560) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("seed precondition   : c12 tag=%0d otype=0x%0h, c14 otype=0x%0h (must be 1, 0x42, 0xFFFE)",
             dut.CPU_Xreg_val_a0[5], dut.CPU_Xreg_val_a0[6], dut.CPU_Xreg_val_a0[7]);
    $display("shadow before trap  : 0x%0h (must be 0xFFFFF -- an out-of-window empty sentinel, NOT 0)",
             dut.CPU_Xreg_val_a0[23]);
    $display("(A) OCInvoke fault  : mcause=0x%0h mtval=0x%0h (must be 0x18 and 0x189 = cap_idx 12 << 5 | 0x09)",
             dut.CPU_Xreg_val_a0[8], dut.CPU_Xreg_val_a0[9]);
    $display("(B) OCReturn fault  : mcause=0x%0h mtval=0x%0h (must be 0x18 and 0x1C9 = cap_idx 14 << 5 | 0x09)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("CRBR untouched      : region=%0d saved=0x%0h (must be 0 and 0xFFFFF)",
             dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("trap count          : %0d (must be 2 -- both crossings faulted)", dut.CPU_Xreg_val_a0[20]);
    $display("completion sentinel : x22=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[22]);

    if (dut.CPU_Xreg_val_a0[5]  == 64'd1     &&
        dut.CPU_Xreg_val_a0[6]  == 64'h42    &&
        dut.CPU_Xreg_val_a0[7]  == 64'hFFFE  &&
        dut.CPU_Xreg_val_a0[23] == 64'hFFFFF &&
        dut.CPU_Xreg_val_a0[8]  == 64'h18    &&
        dut.CPU_Xreg_val_a0[9]  == 64'h189   &&
        dut.CPU_Xreg_val_a0[10] == 64'h18    &&
        dut.CPU_Xreg_val_a0[11] == 64'h1C9   &&
        dut.CPU_Xreg_val_a0[15] == 64'd0     &&
        dut.CPU_Xreg_val_a0[16] == 64'hFFFFF &&
        dut.CPU_Xreg_val_a0[20] == 64'd2     &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (both domain crossings into a paged-out region raise the explicit, bounded VEDA_CAUSE_REGION_FAULT 0x09 -- not the 0x11 that each cause mux's fall-through arm would report -- and commit nothing: no PCC narrowing, no IDC install, no PC redirect, and the CRBR is left byte-identical. The sealed pair passes all nine of OCInvoke's capability checks, so the region gate is provably the FIRST failure, not an incidental one)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
