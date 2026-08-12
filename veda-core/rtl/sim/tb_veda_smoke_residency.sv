`timescale 1ns/1ps
// RTL-6 (DESIGN_02 Phase 2, increment 1): the OBJECT RESIDENCY GATE.
//
// x21/x22/x23 -- plain Bind / Bind-NoTrap / Rebind each hard-trapped with
//                cause 0x0A and the correct cap_idx in mtval.
// x26         -- the plain-Bind destination was left completely untouched
//                (Tag still 0), not merely soft-failed.
// x28         -- a resident object still binds normally afterwards.
// x30         -- 0xD09E only if every check above passed.
//
// THE odt_mem PROBE IS THE POINT OF THE TESTBENCH SIDE, and it checks
// something the .S cannot see at all. A residency-faulting Bind must not
// claim ownership. Object_ID=104 is seeded unowned (0xFF); if the owner
// byte reads anything else, a trapping instruction wrote architectural
// state. That write lives in its own always_ff behind BOGUS_USE, invisible
// to TLV-level review, and because page-in is specified to PRESERVE
// owner_hart the stolen ownership would survive the entire paging cycle --
// so it would outlive the fault that created it and never be attributable
// back to here.
//
// Entry 104 -> byte offset 104*32 = 3328; owner_hart at +18, resident +25.
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

    repeat (140) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x21(bind)=0x%0h x22(notrap)=0x%0h x23(rebind)=0x%0h x26(untouched)=0x%0h x28(resident ok)=0x%0h x30=0x%0h",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
              dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[30]);
    $display("odt_mem[Object_ID=104]: valid=%0b resident=%0b owner=0x%0h",
              dut.odt_mem[32'h9000_0000+3328+17][0],
              dut.odt_mem[32'h9000_0000+3328+25][0],
              dut.odt_mem[32'h9000_0000+3328+18]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[28] == 64'h600D &&
        // PART C: a live capability rebound onto a paged-out object kept
        // its own Base and Tag. Added after mutation testing showed
        // Rebind's exclusion could be deleted with every other check
        // still passing.
        dut.CPU_Xreg_val_a0[19] == 64'h600D &&
        // the fixture is still valid, still non-resident, and still UNOWNED
        dut.odt_mem[32'h9000_0000+3328+17][0] == 1'b1 &&
        dut.odt_mem[32'h9000_0000+3328+25][0] == 1'b0 &&
        dut.odt_mem[32'h9000_0000+3328+18]    == 8'hFF) begin
      $display("\n*** TEST PASSED *** (object residency gate: all three bind modes hard-trap 0x0A, nothing committed, ownership not claimed, resident objects unaffected)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
