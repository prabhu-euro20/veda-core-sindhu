`timescale 1ns/1ps
// R74 -- the retain mask was unreachable by the only software that needs it.
//
// R71 put the crossing's retain mask in CSR 0x7CA. Privilege here is derived
// from the CSR ADDRESS -- csrPriv(csr) = csr[9..8] -- so 0x7CA was Machine-only,
// while R71's own text told compartments to set it themselves. Compartments are
// unprivileged by definition. Measured: veda_smoke_r48_oda_crossing.S writes the
// mask after its drop to User and its trap counter read 2, not 1. The write
// trapped, the mask stayed zero, and the suite passed 110/110 anyway.
//
// Moved to 0x8CA: per the official RISC-V Privileged specification's CSR
// address-allocation table, 0x800-0x8FF is the only Custom read/write USER-level
// range, and custom addresses are guaranteed never to be redefined by future
// standard extensions. No privilege-check logic changed on either layer.
//
// The second assertion below is the load-bearing one: RETAIN NEVER BECOMES
// GRANT. c9 is retained while holding nothing and must come out of the crossing
// still empty AND still unusable.
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (9000) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("R74 traps at the User CSR write : x20=0x%0h (must be 0 -- it used to trap)", dut.CPU_Xreg_val_a0[20]);
    $display("R74 delegated value read at User: x21=0x%0h (must be 0xC0FFEE)", dut.CPU_Xreg_val_a0[21]);
    $display("R74 retained EMPTY register tag : x22=0x%0h (must be 0 -- retain is not grant)", dut.CPU_Xreg_val_a0[22]);
    $display("R74 traps before the deliberate : x23=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[23]);
    $display("R74 traps after using the empty : x24=0x%0h (must be 1)", dut.CPU_Xreg_val_a0[24]);
    $display("R74 value read through the empty: x25=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[25]);
    $display("R74 that trap's mtval           : x26=0x%0h (low 5 bits must be 0x02 TAG)", dut.CPU_Xreg_val_a0[26]);
    $display("R74 verdict                     : x19=0x%0h (must be 0x600D)", dut.CPU_Xreg_val_a0[19]);
    if (dut.CPU_Xreg_val_a0[19] == 64'h600D &&
        dut.CPU_Xreg_val_a0[20] == 64'h0 && dut.CPU_Xreg_val_a0[21] == 64'hC0FFEE &&
        dut.CPU_Xreg_val_a0[22] == 64'h0 && dut.CPU_Xreg_val_a0[23] == 64'h0 &&
        dut.CPU_Xreg_val_a0[24] == 64'h1 && dut.CPU_Xreg_val_a0[25] == 64'h0 &&
        (dut.CPU_Xreg_val_a0[26] & 64'h1F) == 64'h02)
      $display("\n*** TEST PASSED *** (an unprivileged compartment arms the retain mask and delegates its own capability across the crossing, and a retained but EMPTY register stays empty and stays unusable -- retain never becomes grant)");
    else
      $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
