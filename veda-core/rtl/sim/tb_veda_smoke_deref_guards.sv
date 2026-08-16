`timescale 1ns/1ps
// P1-P6: $veda_sealed survived on six of seven chains. A sealed capability is
//   opaque by design -- the basis of compartment entry sentries -- so one that
//   can still be dereferenced is a hole through a compartment boundary.
//   c3 sealed, cause 0x03 -> mtval 0x63 on every path.
// P7-P9: bounds as a TRAP DECISION on nmc.d/nmc.w/atomic, through a Length-0
//   capability to a NON-cow object. veda_smoke_check_order.S asserts BOUNDS on
//   these same three but its object is also cow, so cow fires the trap and the
//   cause chain still reports 0x01 -- it verifies the cause ORDER, not the trap
//   DECISION. c4, cause 0x01 -> mtval 0x81.
// Control: the unsealed capability to the same object still round-trips 0x600D,
//   and the trap count is exactly 9.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1100) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("sealed -- ocs.d=0x%0h ocl.d=0x%0h ocs.c=0x%0h ocl.c=0x%0h nmc.d=0x%0h nmc.w=0x%0h atomic=0x%0h  (all want 0x63)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11], dut.CPU_Xreg_val_a0[12],
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[23]);
    $display("bounds-as-trap (non-cow) -- nmc.d=0x%0h nmc.w=0x%0h atomic=0x%0h  (all want 0x81)",
             dut.CPU_Xreg_val_a0[16], dut.CPU_Xreg_val_a0[17], dut.CPU_Xreg_val_a0[18]);
    $display("control -- unsealed read-back=0x%0h (want 0x600D)   traps=%0d (want 10)",
             dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[21]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h63 && dut.CPU_Xreg_val_a0[11] == 64'h63 &&
        dut.CPU_Xreg_val_a0[12] == 64'h63 && dut.CPU_Xreg_val_a0[13] == 64'h63 &&
        dut.CPU_Xreg_val_a0[14] == 64'h63 && dut.CPU_Xreg_val_a0[15] == 64'h63 && dut.CPU_Xreg_val_a0[23] == 64'h63 &&
        dut.CPU_Xreg_val_a0[16] == 64'h81 && dut.CPU_Xreg_val_a0[17] == 64'h81 &&
        dut.CPU_Xreg_val_a0[18] == 64'h81 &&
        dut.CPU_Xreg_val_a0[19] == 64'h600D && dut.CPU_Xreg_val_a0[21] == 64'd10) begin
      $display("\n*** TEST PASSED *** (a sealed capability is refused on all six dereference paths, bounds genuinely FIRES the trap on the three capability-offset paths rather than merely winning the cause, and the unsealed capability to the same object still works)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
