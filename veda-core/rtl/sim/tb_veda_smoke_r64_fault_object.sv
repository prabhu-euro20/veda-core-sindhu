`timescale 1ns/1ps
// R64 -- CSR 0x7C9 veda_mfaultobj, the bind-side fault-identification channel
// DESIGN_02:293-297 asked for. See veda_smoke_r64_fault_object.S.
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

    $display("R64 control 1 (resets to the SENTINEL, not 0) : x19=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[19]);
    $display("R64 channel, OBJECT_NOT_FOUND on object 400   : x20=%0d (must be 400)", dut.CPU_Xreg_val_a0[20]);
    $display("R64 fail-closed, an unrelated ecall clears it : x21=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[21]);
    $display("R64 channel, RESIDENCY_FAULT on object 401    : x23=%0d (must be 401 -- the case", dut.CPU_Xreg_val_a0[23]);
    $display("                                                DESIGN_02 asks for: no capability");
    $display("                                                was minted, so nothing else names it)");
    $display("R64 nothing minted, and the run completed     : x24=0x%0h (must be 0x600d)", dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[19] == 64'h600D &&
        dut.CPU_Xreg_val_a0[20] == 64'd400  &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'd401  &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a handler can now name the object that faulted, including on the bind path where no capability was ever minted -- and the channel is fail-closed: any trap that consulted no descriptor reports the sentinel instead of a stale name)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
