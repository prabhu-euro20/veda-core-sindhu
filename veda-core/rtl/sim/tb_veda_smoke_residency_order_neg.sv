`timescale 1ns/1ps
// RTL-6 (DESIGN_02 Phase 2, increment 1): CAUSE-PRIORITY ORDERING for
// RESIDENCY_FAULT (0x0A) against the three causes it can co-occur with.
//
// x21 -- 0x05 outranks 0x0A: a never-populated slot reads valid=0 AND
//        resident=0, and must report "never existed", not "paged out".
// x22 -- 0x0A outranks 0x06: an object both paged out and owned elsewhere
//        must report the SERVICEABLE condition, not the permanent one.
// x23 -- the control for x22: owned elsewhere but resident still gives
//        0x06, so x22 cannot pass by 0x0A having swallowed every
//        wrong-owner case.
// x24 -- 0x09 outranks 0x0A: both region and object non-resident, region
//        wins.
// x26 -- the control for x24: a RESIDENT object in the same non-resident
//        region also gives 0x09, proving the region gate decides both.
//
// Every one of these orderings is a single-token change in the RTL cause
// chain that compiles clean, and none of them is visible to the residency
// gate's own test -- there the correct and incorrect designs agree.
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

    repeat (110) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x21(0x05>0x0A)=0x%0h x22(0x0A>0x06)=0x%0h x23(ctrl 0x06)=0x%0h x24(0x09>0x0A)=0x%0h x26(ctrl 0x09)=0x%0h x30=0x%0h",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
              dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[30]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (cause ordering: 0x05 > 0x0A > 0x06, and 0x09 > 0x0A, each with its own control)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
