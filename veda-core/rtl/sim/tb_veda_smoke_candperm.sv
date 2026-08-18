`timescale 1ns/1ps
// RTL mirror of Sail vc_candperm (positive): CAndPerm attenuates Perms only,
// keeps Base/Tag, and an all-clear mask leaves the capability valid.
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
    repeat (64) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("candperm: orig_perms=0x%0h masked_perms=0x%0h masked_tag=%0b base=0x%0h  clear_perms=0x%0h clear_tag=%0b",
              dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12],
              dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h103C &&   // original perms
        dut.CPU_Xreg_val_a0[11] == 64'h000C &&   // 0x103C & 0x000C
        dut.CPU_Xreg_val_a0[12] == 64'h1    &&   // tag survives attenuation
        dut.CPU_Xreg_val_a0[13] == 64'h80010000 && // base untouched
        dut.CPU_Xreg_val_a0[14] == 64'h0    &&   // all perms cleared
        dut.CPU_Xreg_val_a0[15] == 64'h1) begin  // yet still tagged (weaker, not destroyed)
      $display("\n*** TEST PASSED *** (CAndPerm attenuates Perms, keeps Base/Tag, all-clear stays valid)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end
    $finish;
  end
endmodule
