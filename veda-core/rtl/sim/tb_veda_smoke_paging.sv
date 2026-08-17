`timescale 1ns/1ps
// RTL-6c: the page-out / page-in cycle, and what page-in preserves.
//
// x22 -- object minted, bound and round-tripped before any paging
// x23 -- page-out succeeded and wrote rd = 0
// x24 -- the held capability went STALE (0x02), not merely unusable:
//        page-out's generation bump is what invalidates it
// x26 -- re-Binding a paged-out object reports RESIDENCY (0x0A), telling
//        a pager the object is serviceable rather than destroyed
// x27 -- page-in succeeded
// x29 -- the object really MOVED: new Base differs from old
// x30 -- and it works at the new location
// x31 -- generation was PRESERVED across page-in (second page-out still
//        allowed from a fixture two steps below the ceiling)
// x13 -- the third page-out is refused at the ceiling
// x14 -- owner_hart was PRESERVED (Bind still refuses 0x06 afterwards)
// x15 -- 0xD09E only if all of the above held
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

    repeat (1200) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x22=0x%0h x23=0x%0h x24=0x%0h x26=0x%0h x27=0x%0h x29=0x%0h x30=0x%0h x31=0x%0h x13=0x%0h x14=0x%0h x15=0x%0h",
              dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23], dut.CPU_Xreg_val_a0[24],
              dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[27], dut.CPU_Xreg_val_a0[29],
              dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[31], dut.CPU_Xreg_val_a0[13],
              dut.CPU_Xreg_val_a0[14], dut.CPU_Xreg_val_a0[15]);
    $display("old Base x21=0x%0h  new Base x28=0x%0h  traps x20=%0d",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[28], dut.CPU_Xreg_val_a0[20]);
    $display("odt_mem[Object_ID=103]: valid=%0b resident=%0b",
              dut.odt_mem[32'h9000_0000+103*32+17][0],
              dut.odt_mem[32'h9000_0000+103*32+25][0]);

    if (dut.CPU_Xreg_val_a0[15] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[27] == 64'h600D &&
        dut.CPU_Xreg_val_a0[29] == 64'h600D &&
        dut.CPU_Xreg_val_a0[30] == 64'h600D &&
        dut.CPU_Xreg_val_a0[31] == 64'h600D &&
        dut.CPU_Xreg_val_a0[13] == 64'h600D &&
        dut.CPU_Xreg_val_a0[14] == 64'h600D &&
        // the paged-in object ends valid AND resident, checked directly
        dut.odt_mem[32'h9000_0000+103*32+17][0] == 1'b1 &&
        dut.odt_mem[32'h9000_0000+103*32+25][0] == 1'b1) begin
      $display("\n*** TEST PASSED *** (paging cycle: page-out invalidates, page-in relocates and preserves generation and owner_hart)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
