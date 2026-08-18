`timescale 1ns/1ps
// R59 -- a re-minted object inherited the previous occupant's owner.
// See veda_smoke_r59_owner_reset.S for the full reasoning. Entries 60 and 105
// are seeded owner_hart = 0x63 ("hart 99") by Milestone 12's fixture; 109 is the
// untouched control that proves owner_ok is still being checked at all.
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
    repeat (3000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("R59 control 1 (seeded slot refuses)      : x20=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[20]);
    $display("R59 re-minted slot binds                 : x21=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[21]);
    $display("R59 control 2 (and is usable)            : x22=0x%0h (must be 0xc0ffee)", dut.CPU_Xreg_val_a0[22]);
    $display("R59 control 3 (untouched slot refuses)   : x23=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[23]);
    $display("R59 destroy half                         : x24=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h600D &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'hC0FFEE &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (Populate and Destroy both reset owner_hart, so a re-minted slot is unowned -- while an untouched slot seeded to another hart is still refused, proving owner_ok is being checked and not merely bypassed)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
