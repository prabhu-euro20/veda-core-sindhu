`timescale 1ns/1ps
// Negative control for RTL Milestone 4: `veda.droppriv` first, then an
// ODT-Populate attempt against a never-before-seeded Object_ID must be a
// real no-op -- verified two ways: (1) through the ISA itself, matching
// Milestone 3's own "verify through a subsequent real instruction"
// discipline -- a Bind against that Object_ID must come back Tag=0,
// since no ODT entry was ever actually created; (2) directly against
// odt_mem[] itself, confirming the write genuinely never happened (not
// just that Bind's own separate check happened to also fail).
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

    repeat (90) begin
      @(posedge clk);
      #1;
      $display("cyc=%0d pc=0x%0h instr=0x%08h | priv=%0b is_odt_pop=%0b pop_viol=%0b",
                cyc_cnt, dut.CPU_pc_a0, dut.CPU_instr_a0,
                dut.CPU_priv_a0, dut.CPU_is_veda_odt_populate_a0, dut.CPU_veda_odt_populate_violation_a0);
      cyc_cnt = cyc_cnt + 1;
    end

    // RTL-6 FIX -- this probe was STALE AND DEAD, and it was dead inside
    // the pass condition, not merely in the $display.
    //
    // It was written for the original 16-byte entry (valid at +9), so it
    // read byte 16*5+9 = 89. Under the 32-byte layout RTL-3 introduced,
    // byte 89 is entry 2's offset +25 -- a spare byte that was always 0.
    // The conjunct was therefore VACUOUSLY TRUE from RTL-3 onward: this
    // negative test's entire odt_mem-side assertion, the half its own
    // header comment calls "verified two ways", had been proving nothing
    // for three increments. Only the Tag=0 check was live.
    //
    // Found by RTL-6, and found the hard way: +25 is exactly where the new
    // `resident` byte lands, so the dead conjunct came back to life
    // reading a real field with unrelated semantics and flipped the test
    // to FAIL. A silently-dead assertion is worse than a missing one --
    // this suite counted it as coverage for three increments.
    //
    // Correct address for Object_ID=5's valid byte: entry 5 (region 0,
    // local 5), so 5*ODT_ENTRY_BYTES + 17 = 5*32 + 17 = 177.
    $display("x6(c0 tag)=%0b odt_mem[Object_ID=5]: valid=%0b traps=%0d mcause=0x%0h",
              dut.CPU_Xreg_val_a0[6], dut.odt_mem[32'h9000_0000+32*5+17][0], dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[6] == 64'h0 &&
        dut.CPU_Xreg_val_a0[20] == 64'h1 &&   // RTL-11 (R14): it TRAPPED, once
        dut.CPU_Xreg_val_a0[21] == 64'h2 &&   // and the cause is illegal-instruction
        dut.odt_mem[32'h9000_0000+32*5+17][0] == 1'b0) begin
      $display("\n*** TEST PASSED *** (dropped privilege correctly blocked ODT-Populate -- no ODT entry was ever created, confirmed both via odt_mem[] directly and via a subsequent Bind's own Tag=0)");
    end else begin
      $display("\n*** TEST FAILED *** (privilege gate did NOT block ODT-Populate)");
    end

    $finish;
  end
endmodule
