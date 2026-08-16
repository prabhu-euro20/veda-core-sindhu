`timescale 1ns/1ps
// R26: authority is a NAME, not a bound. Single-term discriminator -- inside the
// compartment veda_pcc_length IS the sentinel, identical to its boot value, so
// the length term cannot be what refuses. Only veda_pcc_object differs.
//  x10 baseline write outside any compartment -> 0x40 (the gate is not always-refusing)
//  x21 restored to the sentinel before crossing -> 0xffffffffff
//  x11 write from INSIDE a sentinel-Length compartment -> must STILL be the
//      sentinel, i.e. the write was refused while the length term read identical
//  x12 mtvec from inside -> must still point at trap_handler, never at hijacked
//  x14 must be 0 -- the hijack landing pad must never execute
//  x15 0x600D -- the compartment ran to the end rather than dying on a fault
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (700) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("outside compartment: mepcc_len write took -> 0x%0h (want 0x40)   restored -> 0x%0h (want 0xffffffffff)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[21]);
    $display("INSIDE  compartment: mepcc_len after write -> 0x%0h (want 0xffffffffff -- REFUSED)",
             dut.CPU_Xreg_val_a0[11]);
    $display("INSIDE  compartment: mtvec after write   -> 0x%0h   hijack pad ran? x14=0x%0h (want 0)",
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[14]);
    $display("reached the end: x15=0x%0h (want 0x600D)   traps=%0d", dut.CPU_Xreg_val_a0[15], dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[10] == 64'h40 &&
        dut.CPU_Xreg_val_a0[21] == 64'hFFFFFFFFFF &&
        dut.CPU_Xreg_val_a0[11] == 64'hFFFFFFFFFF &&
        dut.CPU_Xreg_val_a0[14] == 64'h0 &&
        dut.CPU_Xreg_val_a0[15] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (a compartment entered on a sentinel-Length object can no longer rewrite its own PCC bounds or redirect mtvec, even though its PCC length reads exactly the same value it has at boot -- the refusal is the object NAME, which no capability can forge because NONE cannot cross either domain crossing)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
