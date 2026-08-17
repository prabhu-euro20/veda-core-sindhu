`timescale 1ns/1ps
// RTL-12: CAndPerm attenuation is ENFORCED, on all three store paths.
//
// x22 -- positive control: the full capability round-trips
// x23 -- OCS.D through a store-stripped capability trapped, mtval 0x33
// x24 -- that capability still LOADS, and still reads the original value, so
//        the refused store never reached memory
// x25 -- OCL.D through a load-stripped capability trapped, mtval 0x92
// x26 -- that capability still STORES -- attenuation is precise both ways
// x27 -- OCS.C, the second store path, trapped too
// x28 -- the Veda-Atomic path, the third, trapped too
// x29 -- and memory still holds phase 5's value: three refusals, no half-apply
// x11 -- the atomic path checks LOAD permission too, and that needs its own
//        phase: stripping store never exercises it
// x14 -- CAndPerm carries the GENERATION -- provable only on an object whose
//        generation is non-zero, since 0 == 0 hides a lost one
// x30 -- 0xD09E only if all of the above held, in exactly five traps
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

    repeat (2400) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x22(ctrl)=0x%0h x23(ocsd mtval)=0x%0h x24(still loads)=0x%0h x25(ocld mtval)=0x%0h x26(still stores)=0x%0h x27(ocsc mtval)=0x%0h x28(atomic mtval)=0x%0h x29(nohalf)=0x%0h x11(atomic-load)=0x%0h x14(gen-carry)=0x%0h x30=0x%0h traps=%0d",
              dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24],
              dut.CPU_Xreg_val_a0[25], dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[27],
              dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[29], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[30],
              dut.CPU_Xreg_val_a0[20]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[23] == 64'h33 &&
        dut.CPU_Xreg_val_a0[25] == 64'h92 &&
        (dut.CPU_Xreg_val_a0[27] & 64'h1F) == 64'h13 &&
        (dut.CPU_Xreg_val_a0[28] & 64'h1F) == 64'h13 &&
        dut.CPU_Xreg_val_a0[11] == 64'h92 &&
        dut.CPU_Xreg_val_a0[14] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (rights attenuation is enforced on all three store paths and on the load path, and is precise -- the untouched right still works)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
