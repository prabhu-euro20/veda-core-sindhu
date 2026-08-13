`timescale 1ns/1ps
// RTL-10 (R13): Destroy may not clear a slot it does not own.
//
// x21 -- object 32 populated and readable to begin with
// x22 -- after destroying the ALIAS 288, object 32 still re-Binds and reads
// x23 -- and the capability minted BEFORE the aliased destroy still works,
//        so no generation was bumped underneath it
// x24 -- the control: destroying 32 by its OWN name still works (exactly one
//        trap, from the Bind that must now fail)
// x30 -- 0xD09E only if all of the above held
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

    $display("x21(setup)=0x%0h x22(rebind)=0x%0h x23(oldcap)=0x%0h x24(control)=0x%0h x30=0x%0h traps=%0d",
              dut.CPU_Xreg_val_a0[21], dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[23],
              dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[30], dut.CPU_Xreg_val_a0[20]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[21] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[23] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D) begin
      $display("\n*** TEST PASSED *** (aliased Destroy is a no-op on a slot it does not own, while Destroy by the object's own name still works)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
