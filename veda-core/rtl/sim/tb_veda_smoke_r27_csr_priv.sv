`timescale 1ns/1ps
// R39: a CSR access below the address's own privilege is an illegal
// instruction. This testbench used to assert a trap count of ZERO and call that
// Sail parity; the model traps, and it traps on reads as well as writes.
//  x13 = 0xBAD   an unprivileged CSR READ never executed
//  x20 = 11      one trap per refused access, plus the final ecall
//  x21 = 0       the trap vector the unprivileged code tried to install never ran
//  x22 = 0x600D  privileged read-back found every register untouched
module tb;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  initial begin
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (1600) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    $display("privileged capture : pcc_len=0x%0h pcc_base=0x%0h mepcc_len=0x%0h mepcc_base=0x%0h",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11],
             dut.CPU_Xreg_val_a0[12], dut.CPU_Xreg_val_a0[17]);
    $display("U-mode CSR read    : x13=0x%0h (want 0xBAD -- it never executed)", dut.CPU_Xreg_val_a0[13]);
    $display("trap-vector hijack : x21=0x%0h (want 0 -- the installed handler never ran)", dut.CPU_Xreg_val_a0[21]);
    $display("privileged readback: x22=0x%0h (want 0x600D -- all ten registers untouched)", dut.CPU_Xreg_val_a0[22]);
    $display("traps=%0d (want 11 -- one per refused access, plus the ecall)", dut.CPU_Xreg_val_a0[20]);
    if (dut.CPU_Xreg_val_a0[13] == 64'hBAD &&
        dut.CPU_Xreg_val_a0[21] == 64'd0 &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[20] == 64'd11) begin
      $display("\n*** TEST PASSED *** (all ten Machine-only CSRs refuse an unprivileged access with a real Illegal_Instruction, reads included -- mtvec among them, which unprivileged code outside a compartment could previously have replaced with its own trap vector, and mscratch/mepc/mcause/mtval, which had no guard at all)");
    end else $display("\n*** TEST FAILED ***");
    $finish;
  end
endmodule
