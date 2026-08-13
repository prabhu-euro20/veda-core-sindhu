`timescale 1ns/1ps
// RTL-7 (R11): a domain crossing must revalidate its code object.
//
// x21 -- OCInvoke through a paged-out code object trapped 0x02
// x22 -- OCReturn likewise. Sail mutation testing proved this arm needs
//        its own coverage: deleting OCRETURN's revalidation left the whole
//        suite passing while the other two crossings were covered.
// x23 -- the positive control: a crossing into a live resident object
//        still lands
// x30 -- 0xD09E only if all of the above held
//
// The cause is 0x02 rather than 0x0A because page-out bumps the
// generation, so a held capability fails the generation check first. The
// capability is permanently dead; the object is still serviceable, and
// software learns that by re-Binding.
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

    repeat (330) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x21(ocinvoke)=0x%0h x22(ocreturn)=0x%0h x23(control)=0x%0h x24(ocjalr)=0x%0h x30=0x%0h traps=%0d last mtval=0x%0h",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24],
              dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20], dut.CPU_Xreg_val_a0[25]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[27] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (crossing revalidation: OCInvoke and OCReturn both refuse an evicted code object, a live one still crosses)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
