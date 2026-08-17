`timescale 1ns/1ps
// RTL-6c: what the paging pair REFUSES, and that no refusal half-applies.
//
// x23 -- page-in refuses a LIVE object (the silent-relocation attack)
// x24 -- and did not half-apply: Base unmoved, capability still valid
// x26 -- one legal page-out succeeds
// x27 -- a second page-out on the same object is refused
// x28 -- and did not half-apply: still reports RESIDENCY, nothing else
// x29 -- one page-out at generation 0xFFFFFE reaches the ceiling legally
// x30 -- the next page-out is REFUSED: the saturation fail-closed
// x31 -- and did not half-apply: residency intact, object still usable.
//        This is the assertion that matters -- a refusal that still
//        cleared residency would have produced exactly the {valid,
//        non-resident, saturated} state whose page-in is a use-after-free
// x18 -- without authority, both instructions are refused
// x19 -- 0xD09E only if all of the above held
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

    repeat (1520) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x23=0x%0h x24=0x%0h x26=0x%0h x27=0x%0h x28=0x%0h x29=0x%0h x30=0x%0h x31=0x%0h x18=0x%0h x19=0x%0h traps=%0d",
              dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[26],
              dut.CPU_Xreg_val_a0[27], dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[29],
              dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[31], dut.CPU_Xreg_val_a0[18],
              dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[20]);
    $display("odt_mem[Object_ID=106] after the refused page-out: valid=%0b resident=%0b",
              dut.odt_mem[32'h9000_0000+106*32+17][0],
              dut.odt_mem[32'h9000_0000+106*32+25][0]);

    if (dut.CPU_Xreg_val_a0[19] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[27] == 64'h600D &&
        dut.CPU_Xreg_val_a0[28] == 64'h600D &&
        dut.CPU_Xreg_val_a0[29] == 64'h600D &&
        dut.CPU_Xreg_val_a0[30] == 64'h600D &&
        dut.CPU_Xreg_val_a0[31] == 64'h600D &&
        dut.CPU_Xreg_val_a0[18] == 64'h600D &&
        dut.CPU_Xreg_val_a0[14] == 64'h600D &&
        // the saturated object survived its refused page-out intact
        dut.odt_mem[32'h9000_0000+106*32+17][0] == 1'b1 &&
        dut.odt_mem[32'h9000_0000+106*32+25][0] == 1'b1) begin
      $display("\n*** TEST PASSED *** (paging refusals: live page-in, double page-out, generation saturation and missing authority all refused, none half-applied)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
