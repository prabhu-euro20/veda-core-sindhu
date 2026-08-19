`timescale 1ns/1ps
// R73 -- a domain refusal is mode-dependent, like every other refusal on veda.bind.
//
// The per-object bind gate used to trap for ALL THREE bind modes. It was written
// beside the residency gate and inherited residency's all-modes policy without
// inheriting residency's ARGUMENT: region and residency trap for every mode so
// the holder goes and SERVICES something ("paged out, retry"), and a domain
// refusal has nothing to service. Milestone 12 set the rule for ownership
// refusals -- plain Bind hard-traps, Bind-NoTrap soft-fails -- and the
// owner_hart arm still implements it. This gate was the silent exception, and
// R43 justified a design decision by citing a sentence it made false.
//
// Three modes, three different correct answers, all asserted here. The
// plain-Bind row is the ANTI-VACUITY CONTROL: without it a core that simply
// DELETED the domain gate would satisfy both soft-fail rows.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (9000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R73 setup traps                 : x28=0x%0h (must be 0)",        dut.CPU_Xreg_val_a0[28]);
    $display("R73 ROW1 Rebind reference Base  : x20=0x%0h (must be nonzero)",  dut.CPU_Xreg_val_a0[20]);
    $display("R73 ROW1 Rebind tag             : x21=0x%0h (must be 0)",        dut.CPU_Xreg_val_a0[21]);
    $display("R73 ROW1 Rebind Base AFTER      : x22=0x%0h (must EQUAL x20)",   dut.CPU_Xreg_val_a0[22]);
    $display("R73 ROW2 NoTrap tag             : x23=0x%0h (must be 0)",        dut.CPU_Xreg_val_a0[23]);
    $display("R73 ROW2 NoTrap Base AFTER      : x24=0x%0h (must be 0 -- a DIFFERENT shape)", dut.CPU_Xreg_val_a0[24]);
    $display("R73 traps after both soft-fails : x25=0x%0h (must be 0)",        dut.CPU_Xreg_val_a0[25]);
    $display("R73 total traps                 : x27=0x%0h (must be 1 -- the LOUD one)", dut.CPU_Xreg_val_a0[27]);
    $display("R73 loud refusal mtval          : x26=0x%0h (low 5 bits must be 0x0B)",   dut.CPU_Xreg_val_a0[26]);
    $display("R73 verdict                     : x19=0x%0h (must be 0x600D)",   dut.CPU_Xreg_val_a0[19]);
    if (dut.CPU_Xreg_val_a0[19] == 64'h600D &&
        dut.CPU_Xreg_val_a0[20] != 64'h0 &&
        dut.CPU_Xreg_val_a0[22] == dut.CPU_Xreg_val_a0[20] &&
        dut.CPU_Xreg_val_a0[21] == 64'h0 && dut.CPU_Xreg_val_a0[23] == 64'h0 &&
        dut.CPU_Xreg_val_a0[24] == 64'h0 && dut.CPU_Xreg_val_a0[25] == 64'h0 &&
        dut.CPU_Xreg_val_a0[27] == 64'h1 && (dut.CPU_Xreg_val_a0[26] & 64'h1F) == 64'h0B)
      $display("\n*** TEST PASSED *** (Rebind clears Tag and PRESERVES Base, Bind-NoTrap ZEROES the register, neither traps, and plain Bind still refuses loudly with DOMAIN_VIOLATION)");
    else
      $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
