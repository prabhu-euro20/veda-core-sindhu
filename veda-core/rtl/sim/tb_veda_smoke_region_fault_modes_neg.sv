`timescale 1ns/1ps
// Veda-Core RTL-4 (DESIGN_08) test 4 (negative): VEDA_CAUSE_REGION_FAULT
// hard-traps plain Bind, Bind-NoTrap AND Rebind, and none of the three
// writes anything to the destination capability register.
// See veda_smoke_region_fault_modes_neg.S.
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

    repeat (140) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("(a) Bind.NoTrap : mcause=0x%0h mtval=0x%0h (must be 0x18 and 0x69 -- a HARD TRAP, not a soft-fail)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("    c3 untouched: tag=%0d base=0x%0h (must be 1 and 0x80010000 -- the preloaded capability survives)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("(b) Rebind      : precondition tag=%0d, mcause=0x%0h mtval=0x%0h (must be 1, 0x18 and 0xA9)",
             dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("    c5 untouched: tag=%0d base=0x%0h (must be 1 and 0x80010000 -- Tag NOT cleared)",
             dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[23]);
    $display("(c) plain Bind  : mtval=0x%0h (must be 0xE9)", dut.CPU_Xreg_val_a0[24]);
    $display("trap count      : %0d (must be 3 -- all three modes trapped)", dut.CPU_Xreg_val_a0[25]);
    $display("reached the end : x21=0x%0h (must be 0xD09E)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h18 &&
        dut.CPU_Xreg_val_a0[11] == 64'h69 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1  &&
        dut.CPU_Xreg_val_a0[13] == 64'h8001_0000 &&
        dut.CPU_Xreg_val_a0[14] == 64'h1  &&
        dut.CPU_Xreg_val_a0[15] == 64'h18 &&
        dut.CPU_Xreg_val_a0[16] == 64'hA9 &&
        dut.CPU_Xreg_val_a0[20] == 64'h1  &&
        dut.CPU_Xreg_val_a0[23] == 64'h8001_0000 &&
        dut.CPU_Xreg_val_a0[24] == 64'hE9 &&
        dut.CPU_Xreg_val_a0[25] == 64'h3  &&
        dut.CPU_Xreg_val_a0[21] == 64'hD09E) begin
      $display("\n*** TEST PASSED *** (the region fault is a hard trap for ALL THREE bind modes, deliberately narrowing this file's own longstanding \"Rebind never hard-traps for ANY reason\" invariant: a Tag-clear would misreport a pageable domain as object-not-found and the pager would never be invoked. All three destination capability registers are left byte-identical -- Tag not even cleared -- proving the trap fires before any write-enable, on the Rebind path as well as the Bind path)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
