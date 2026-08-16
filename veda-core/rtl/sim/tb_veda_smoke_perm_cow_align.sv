`timescale 1ns/1ps
// The last seven census survivors, each mechanism isolated so no other term can
// do its work -- the failure that let check_order's bounds phases pass while
// copy-on-write silently fired their traps.
//  x10-x12  !perm_load_ok on oclc / nmc.w / nmc.d, via CAndPerm(0xFFFB) -> 0xB2
//  x13      capmem_misaligned on oclc, offset 8, in bounds            -> 0x28
//  x14-x16  cow_write on ocsc / nmc.w / atomic, capability bound BEFORE
//           set.cow so it keeps store and only cow can fire           -> 0xCC
//  x17      control read-back 0x600D    x18 trap count, exactly 7
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1100) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("no-load  -- ocl.c=0x%0h nmc.w=0x%0h nmc.d=0x%0h  (all want 0xB2)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12]);
    $display("misalign -- ocl.c=0x%0h  (want 0x28)", dut.CPU_Xreg_val_a0[13]);
    $display("cow      -- ocs.c=0x%0h nmc.w=0x%0h atomic=0x%0h  (all want 0xCC)",
             dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[16]);
    $display("control  -- read-back=0x%0h (want 0x600D)   traps=%0d (want 7)",
             dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[18]);
    if (dut.CPU_Xreg_val_a0[10] == 64'hB2 && dut.CPU_Xreg_val_a0[11] == 64'hB2 &&
        dut.CPU_Xreg_val_a0[12] == 64'hB2 && dut.CPU_Xreg_val_a0[13] == 64'h28 &&
        dut.CPU_Xreg_val_a0[14] == 64'hCC && dut.CPU_Xreg_val_a0[15] == 64'hCC &&
        dut.CPU_Xreg_val_a0[16] == 64'hCC && dut.CPU_Xreg_val_a0[17] == 64'h600D &&
        dut.CPU_Xreg_val_a0[18] == 64'd7) begin
      $display("\n*** TEST PASSED *** (load permission, the capability-granule alignment rule, and copy-on-write each refuse on their own paths with no other term able to fire in their place)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
