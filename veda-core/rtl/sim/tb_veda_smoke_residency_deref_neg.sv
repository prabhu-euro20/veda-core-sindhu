`timescale 1ns/1ps
// RTL-6b: the DEREFERENCE-SIDE object residency check and its position in
// the cause chain.
//
// x21 -- OCL.D through a paged-out object reports 0x0A
// x22 -- OCS.D likewise (the store family)
// x23 -- an out-of-bounds access on the SAME object reports 0x01, not
//        0x0A: bounds still outranks residency, which is what promoting
//        bounds from implicit default to explicit arm in all seven cause
//        chains exists to preserve
// x24 -- NMC reports its own missing-permission cause 0x1f, correctly
//        ahead of residency
// x26 -- OCL.C, the capability-load family
// x27 -- the control: a resident object still stores and loads normally
// x30 -- 0xD09E only if all of the above held
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

    repeat (1040) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x21(ocl.d)=0x%0h x22(ocs.d)=0x%0h x23(oob>resident)=0x%0h x24(nmc.d)=0x%0h x28(nmc.w)=0x%0h x26(ocl.c)=0x%0h x29(ocs.c)=0x%0h x17(atomic)=0x%0h x18(nmc oob)=0x%0h x27(control)=0x%0h x30=0x%0h",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
              dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[26],
              dut.CPU_Xreg_val_a0[29], dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[18],
              dut.CPU_Xreg_val_a0[27], dut.CPU_Xreg_val_a0[30]);
    $display("trap count x20=%0d last mtval x25=0x%0h", dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[25]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[27] == 64'h600D &&
        dut.CPU_Xreg_val_a0[28] == 64'h600D &&
        dut.CPU_Xreg_val_a0[29] == 64'h600D &&
        dut.CPU_Xreg_val_a0[17] == 64'h600D &&
        dut.CPU_Xreg_val_a0[18] == 64'h600D &&
        dut.CPU_Xreg_val_a0[19] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (dereference-side residency: load/store/capload/NMC all check it, bounds and permission still outrank it, resident objects unaffected)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
