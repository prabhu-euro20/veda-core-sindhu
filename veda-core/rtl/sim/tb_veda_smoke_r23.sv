`timescale 1ns/1ps
// R23 -- the two RTL-only defects found while grounding the R19 check-reorder.
//
// x10 -- mtval of the trap Phase A must take. Expect 0x41: mtval is
//        {cap_idx:5, cause:5}, the faulting capability is c2, so
//        (2 << 5) | 0x01 = 0x41. The low five bits are BOUNDS_VIOLATION 0x01.
//        Under the old 65'd16 width no trap fires at all and this reads 0,
//        while the store silently lands 16 bytes past the object.
// x11 -- trap count after Phase A. Must be exactly 1.
// x12 -- Perms of a plain Bind to object 1 BEFORE it is cow. Expect 0x100C
//        (Permit_Load | Permit_Store | Permit_NMC_Compute). Anchors x13.
// x13 -- Perms after set.cow + REBIND. Expect 0x1004 -- bit 3 (Permit_Store)
//        cleared by the 16'hFFF7 mask the Rebind arm was missing. Under the
//        old code this reads 0x100C, i.e. rebinding handed store back.
// x14 -- trap count after Phase C. Must still be 1: an IN-BOUNDS OCS.C on the
//        same object must succeed, or Phase A proves only "OCS.C traps"
//        rather than "OCS.C traps at the right boundary".
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("A: mtval=0x%0h (want 0x41 = c2<<5 | BOUNDS 0x01)   traps_after_A=%0d (want 1)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("B: perms_before_cow=0x%0h (want 0x100C)   perms_after_cow_REBIND=0x%0h (want 0x1004, bit 3 stripped)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[13]);
    $display("C: traps_after_in_bounds_store=%0d (want 1 -- the in-bounds store must NOT trap)",
             dut.CPU_Xreg_val_a0[14]);
    $display("   last mcause=0x%0h (want 0x18)", dut.CPU_Xreg_val_a0[21]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h41   &&
        dut.CPU_Xreg_val_a0[11] == 64'd1    &&
        dut.CPU_Xreg_val_a0[12] == 64'h100C &&
        dut.CPU_Xreg_val_a0[13] == 64'h1004 &&
        dut.CPU_Xreg_val_a0[14] == 64'd1    &&
        dut.CPU_Xreg_val_a0[21] == 64'h18) begin
      $display("\n*** TEST PASSED *** (a 32-byte capability access is bounds-checked at 32 bytes, so a store that would have landed 16 bytes past the object now traps 0x01; and REBIND of a copy-on-write object strips store permission exactly as Bind does; the in-bounds control store still succeeds)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
