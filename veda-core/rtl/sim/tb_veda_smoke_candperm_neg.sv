`timescale 1ns/1ps
// RTL mirror of Sail vc_candperm_neg (negative): attenuating a sealed
// capability clears the Tag (soft-fail), like the OCA/CSetBounds family.
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
    repeat (18) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("candperm_neg: sealed_tag=%0b sealed_otype=0x%0h attenuated_tag=%0b",
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&   // c1 was sealed and valid
        dut.CPU_Xreg_val_a0[11] == 64'h0 &&   // really sealed (otype 0)
        dut.CPU_Xreg_val_a0[12] == 64'h0) begin // attenuating it cleared the Tag
      $display("\n*** TEST PASSED *** (CAndPerm on a sealed capability soft-fails, Tag=0)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
