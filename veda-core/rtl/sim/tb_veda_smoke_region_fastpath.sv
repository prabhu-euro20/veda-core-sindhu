`timescale 1ns/1ps
// Veda-Core RTL-4 (DESIGN_08) test 2: probes the Region-Table read enable
// hierarchically and counts it, the same way tb_veda_smoke_m24_odt_tcm.sv
// already counts dut.CPU_veda_dram_busy_a0. Three intra-domain binds must
// cost ZERO RT reads; one cross-domain bind must cost EXACTLY ONE.
// See veda_smoke_region_fastpath.S.
module tb;
  logic clk = 0;
  logic reset;
  logic [31:0] cyc_cnt = 0;
  wire passed, failed;

  integer rt_reads_total = 0;
  integer rt_reads_phase1 = 0;

  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));

  always #5 clk = ~clk;

  initial begin
    reset = 1;
    repeat (2) @(posedge clk);
    reset = 0;

    repeat (360) begin
      @(posedge clk);
      #1;
      // Sample the RT read enable every cycle. x20 becomes 0xFA57 only
      // after the three intra-domain binds have retired, so anything
      // counted before that belongs to phase 1.
      if (dut.CPU_veda_rt_read_en_a0 === 1'b1) begin
        rt_reads_total = rt_reads_total + 1;
        if (dut.CPU_Xreg_val_a0[20] !== 64'hFA57)
          rt_reads_phase1 = rt_reads_phase1 + 1;
      end
      cyc_cnt = cyc_cnt + 1;
    end

    $display("intra-domain binds ok : x10=%0d x11=%0d x12=%0d (all must be 1)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12]);
    $display("cross-domain bind ok  : x13=%0d base=0x%0h (must be 1 and 0x80020000)",
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14]);
    $display("RT reads, phase 1     : %0d (must be EXACTLY 0 -- three intra-domain binds, CRBR fast path)", rt_reads_phase1);
    $display("RT reads, total       : %0d (must be EXACTLY 1 -- only the one cross-domain bind pays)", rt_reads_total);
    $display("unexpected trap       : x22=0x%0h mcause=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[18]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h1 &&
        dut.CPU_Xreg_val_a0[11] == 64'h1 &&
        dut.CPU_Xreg_val_a0[12] == 64'h1 &&
        dut.CPU_Xreg_val_a0[13] == 64'h1 &&
        dut.CPU_Xreg_val_a0[14] == 64'h8002_0000 &&
        dut.CPU_Xreg_val_a0[21] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[22] == 64'h0 &&
        rt_reads_phase1 == 0 &&
        rt_reads_total  == 1) begin
      $display("\n*** TEST PASSED *** (the CRBR is a single architectural register, not a cache: three intra-domain binds read the Region Table exactly 0 times -- so an intra-domain bind is still ONE memory read, no regression from the pre-DESIGN_08 flat table -- and one cross-domain bind pays exactly 1 extra read and no more. The count depends on which domain the object is in, never on access history, which is what no-cache means here)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
