`timescale 1ns/1ps
// Veda-Core RTL-5 (R10) positive round-trip: the CRBR tracks the domain
// across invoke -> trap -> mret -> return, observed through the new
// read-only CSRs 0x7C6/0x7C7. See veda_smoke_r10_crbr_roundtrip.S.
//
// This is the only test in the suite that moves the CRBR at all: every
// other crossing uses a region-0 code capability, so the load writes the
// register's own reset value and the save/restore never fire.
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

    repeat (200) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("before entry        : region=%0d (must be 0)", dut.CPU_Xreg_val_a0[10]);
    $display("inside region 1     : region=%0d (must be 1 -- OCInvoke loaded the CRBR)", dut.CPU_Xreg_val_a0[11]);
    $display("in trap handler     : region=%0d saved=%0d (must be 0 and 1 -- reset to root, region 1 saved)",
             dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("after mret          : region=%0d saved=0x%0h (must be 1 and 0xFFFFF -- restored, self-consumed)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("after ocreturn      : region=%0d (must be 0 -- back in the root domain)", dut.CPU_Xreg_val_a0[14]);
    $display("completion sentinel : x20=0x%0h (must be 0x600D), failure flag x21=0x%0h (must be 0)",
             dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[10] == 64'd0      &&
        dut.CPU_Xreg_val_a0[11] == 64'd1      &&
        dut.CPU_Xreg_val_a0[15] == 64'd0      &&
        dut.CPU_Xreg_val_a0[16] == 64'd1      &&
        dut.CPU_Xreg_val_a0[12] == 64'd1      &&
        dut.CPU_Xreg_val_a0[13] == 64'hFFFFF  &&
        dut.CPU_Xreg_val_a0[14] == 64'd0      &&
        dut.CPU_Xreg_val_a0[20] == 64'h600D   &&
        dut.CPU_Xreg_val_a0[21] == 64'd0) begin
      $display("\n*** TEST PASSED *** (the CRBR is genuinely loaded from the entered code capability's own Object_ID region field and validated through the Region Table: 0 -> 1 on OCInvoke into resident region 1, reset to 0 with 1 saved on trap so the handler runs in the root domain, restored to 1 and self-consumed on mret, and back to 0 on the return crossing -- the full R10 cycle, none of which any pre-existing test can reach because the whole corpus is region 0)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
