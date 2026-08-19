`timescale 1ns/1ps
// R50 increment 2 -- the crossing clears the capability register file.
//
// R50 measured the possession channel and left it open: OCInvoke's only
// capability write is the IDC, OCReturn writes none, and the dereference
// checker has zero domain terms -- so a callee needs no authority at all, it
// uses a register the caller left bound. R48 closed the mint channel; this
// closes the possession one.
//
// The ABI is CSR 0x7CA veda_xretain: bit i set means capability register i
// survives the next crossing. Never written means zero means retain nothing,
// so silence means clear and never leak. The mask is self-consuming.
//
// THIS TEST CARRIES THE DISCRIMINATION for the whole corpus. The other 50
// crossings declare RETAIN ALL because they measure other mechanisms; delete
// the clear and every one of them still passes. Round 1 fails if the clear is
// absent. Round 2 fails if the mask is ignored and the clear is unconditional
// -- without round 2 a core that simply wiped the file at every crossing would
// satisfy round 1 for entirely the wrong reason, which is the shape this
// project has now found eleven times.
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

    repeat (12000) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("R50i2 round 1 trap count (c10 cleared)   : x20=0x%0h (must be 0x1)",      dut.CPU_Xreg_val_a0[20]);
    $display("R50i2 round 1 mtval cause                : x21=0x%0h (low 5 bits 0x02)",  dut.CPU_Xreg_val_a0[21]);
    $display("R50i2 round 1 value read                 : x22=0x%0h (must be 0x0)",      dut.CPU_Xreg_val_a0[22]);
    $display("R50i2 callee IDC did not return          : x25=0x%0h (must be 0x0)",      dut.CPU_Xreg_val_a0[25]);
    $display("R50i2 round 2 trap count (no NEW trap)   : x23=0x%0h (must be 0x1)",      dut.CPU_Xreg_val_a0[23]);
    $display("R50i2 round 2 value read (mask honoured) : x24=0x%0h (must be 0xC0FFEE)", dut.CPU_Xreg_val_a0[24]);

    if (dut.CPU_Xreg_val_a0[20] == 64'h1 &&
        (dut.CPU_Xreg_val_a0[21] & 64'h1F) == 64'h02 &&
        dut.CPU_Xreg_val_a0[22] == 64'h0 &&
        dut.CPU_Xreg_val_a0[25] == 64'h0 &&
        dut.CPU_Xreg_val_a0[23] == 64'h1 &&
        dut.CPU_Xreg_val_a0[24] == 64'hC0FFEE) begin
      $display("\n*** TEST PASSED *** (the crossing clears the capability file by default: the callee's dereference of the caller's unretained c10 is a TAG violation reading nothing, the callee's IDC does not survive the return leg, and a RETAINED c10 still works -- so the mask is genuinely read and the clear is not unconditional)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
