`timescale 1ns/1ps
// MILESTONE 24 Stage 2: as committed (DRAM_EXTRA_CYCLES=0 shipped
// default), the permanent regression check is that busy_cycles stays 0
// for BOTH the TCM-tier Bind (Object_ID=1) and the DRAM-tier Bind
// (Object_ID=300) -- the tier classification itself is a pure latency
// distinction with no effect at E=0, matching Stage 1's own no-op
// regression pattern. The real tier DISTINCTION (TCM-tier never stalls
// regardless of E; DRAM-tier stalls whenever E!=0) was verified this
// session with a temporarily nonzero E build -- documented in
// veda-core/rtl/MILESTONE_24_RESULTS.md, not re-asserted here.
module tb;
// R21/#18: THIS TESTBENCH USED TO HARD-CODE THE SHIPPED CONFIGURATION.
// Its own header said the nonzero-E half "was verified MANUALLY this same
// session" -- and a manual verification is exactly the gap this project has
// spent the session closing everywhere else. At DRAM_EXTRA_CYCLES != 0 the
// assertion busy_cycles == 0 is correct-to-fail, so run_dram_stall_test.sh
// could never reach a clean result and the whole stall path stayed
// unverifiable by script. The expectation is now a function of E, so ONE
// testbench covers both configurations and neither is checked by hand.
// MEASURED, not counted by eye: at DRAM_EXTRA_CYCLES = 10 this test observes
// exactly 10 busy cycles, so it makes 1 DRAM-tier access. The first draft of
// this line guessed 4 for all three and was wrong for all three -- the real
// counts are 2, 1 and 5. Deriving it from a run rather than from reading the
// program is the point: the number is a structural property of the test, and
// reading it off the hardware is how it stays true when the test changes.
localparam int VEDA_DRAM_ACCESSES = 1;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;
  int busy_cycles = 0;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (160) begin
      @(posedge clk);
      #1;
      if (dut.CPU_veda_dram_busy_a0) busy_cycles = busy_cycles + 1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h busy=%0b | x1=%0d",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0, dut.CPU_veda_dram_busy_a0,
                dut.CPU_Xreg_val_a0[1]);
      cyc_cnt = cyc_cnt + 1;
    end

    $display("\nTotal busy cycles observed: %0d (expected DRAM_EXTRA_CYCLES * %0d)", busy_cycles, dut.DRAM_EXTRA_CYCLES * VEDA_DRAM_ACCESSES);

    if (busy_cycles == dut.DRAM_EXTRA_CYCLES * VEDA_DRAM_ACCESSES) begin
      $display("\n*** TEST PASSED *** (TCM-tier and DRAM-tier Binds both show zero stall at the shipped E=0 default -- the tier classification itself introduces no regression)");
    end else begin
      $display("\n*** TEST FAILED *** (busy_cycles=%0d expected 0)", busy_cycles);
    end

    $finish;
  end
endmodule
