`timescale 1ns/1ps
// Veda-Core RTL-4 (DESIGN_08) test 3 (negative): binding an object whose
// domain is paged out, or whose domain is outside the modeled Region
// Table, raises an explicit VEDA_CAUSE_REGION_FAULT (0x09) -- never a
// silent resolution, and never the object-not-found cause 0x05.
// See veda_smoke_region_fault_neg.S.
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

    repeat (400) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("(a) non-resident region 2 : mcause=0x%0h mtval=0x%0h (must be 0x18 and 0x69 = cap_idx 3 << 5 | 0x09)",
             dut.CPU_Xreg_val_a0[10], dut.CPU_Xreg_val_a0[11]);
    $display("    c3 tag (untouched)    : x12=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[12]);
    $display("(b) out-of-window region 9: mcause=0x%0h mtval=0x%0h (must be 0x18 and 0x89 = cap_idx 4 << 5 | 0x09)",
             dut.CPU_Xreg_val_a0[13], dut.CPU_Xreg_val_a0[14]);
    $display("    c4 tag (untouched)    : x15=0x%0h (must be 0)", dut.CPU_Xreg_val_a0[15]);
    $display("trap count                : x16=%0d (must be 2 -- both bound, both faulted)", dut.CPU_Xreg_val_a0[16]);
    $display("reached the end           : x21=0x%0h (must be 0xD09E)", dut.CPU_Xreg_val_a0[21]);
    // The owner byte of region 2's real, valid, unowned entry (window 2 =
    // entry 512, local 7 -> byte offset (512+7)*32 = 16608, owner at +18).
    // A trapping Bind must not have claimed it.
    $display("region 2 owner byte       : 0x%0h (must be 0xFF/UNOWNED -- the faulting Bind claimed nothing)",
             dut.odt_mem[32'h9000_0000 + 16608 + 18]);

    if (dut.CPU_Xreg_val_a0[10] == 64'h18 &&
        dut.CPU_Xreg_val_a0[11] == 64'h69 &&
        dut.CPU_Xreg_val_a0[12] == 64'h0  &&
        dut.CPU_Xreg_val_a0[13] == 64'h18 &&
        dut.CPU_Xreg_val_a0[14] == 64'h89 &&
        dut.CPU_Xreg_val_a0[15] == 64'h0  &&
        dut.CPU_Xreg_val_a0[16] == 64'h2  &&
        dut.CPU_Xreg_val_a0[21] == 64'hD09E &&
        dut.odt_mem[32'h9000_0000 + 16608 + 18] == 8'hFF) begin
      $display("\n*** TEST PASSED *** (a paged-out domain and an unmodeled domain both raise the explicit, bounded VEDA_CAUSE_REGION_FAULT 0x09 -- not 0x05 object-not-found, which would tell the handler the object never existed instead of telling it to page the domain in and retry. Region 2's object is genuinely seeded, valid and unowned, so a missing residency gate would have made this bind SUCCEED; and the faulting Bind claimed no ownership, leaving the ODT byte-identical)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
