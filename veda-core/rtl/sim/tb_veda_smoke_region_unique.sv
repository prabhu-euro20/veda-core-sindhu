`timescale 1ns/1ps
// Veda-Core RTL-4 (DESIGN_08) test 1: two Object_IDs sharing a local but
// living in different regions are DIFFERENT objects, and a region-1
// capability dereferences correctly through the re-check path.
// See veda_smoke_region_unique.S.
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

    repeat (360) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("region 0 local 1 base : x10=0x%0h (must be 0x80010000)", dut.CPU_Xreg_val_a0[10]);
    $display("region 0 local 1 tag  : x11=0x%0h (must be 1)",          dut.CPU_Xreg_val_a0[11]);
    $display("region 1 local 1 base : x12=0x%0h (must be 0x80020000 -- a DIFFERENT object)", dut.CPU_Xreg_val_a0[12]);
    $display("region 1 local 1 tag  : x13=0x%0h (must be 1 -- RT[1] is resident, so it binds)", dut.CPU_Xreg_val_a0[13]);
    $display("dereference sentinel  : x15=0x%0h (must be 0xD00D -- the re-check resolved through region 1's base)", dut.CPU_Xreg_val_a0[15]);
    $display("unexpected trap       : x22=0x%0h mcause=0x%0h mtval=0x%0h (must all be 0)",
             dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[19]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h8001_0000 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h8002_0000 &&
        dut.CPU_Xreg_val_a0[13] == 64'h1 &&
        dut.CPU_Xreg_val_a0[10] != dut.CPU_Xreg_val_a0[12] &&
        dut.CPU_Xreg_val_a0[15] == 64'hD00D &&
        dut.CPU_Xreg_val_a0[22] == 64'h0) begin
      $display("\n*** TEST PASSED *** (domain-segmented Object_ID gives global uniqueness: {region=0,local=1} and {region=1,local=1} resolve to different ODT entries and yield genuinely different objects, and the region-1 capability dereferences correctly -- proving the Bind path and the dereference re-check resolve through the SAME region base, the one property no region-0 test can reach)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
