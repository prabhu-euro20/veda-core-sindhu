`timescale 1ns/1ps
// RTL-9 (R11(b)): you may not evict the code you are running.
//
// x19 -- the BEFORE control: object 180 was evictable while nothing ran it
// x26 -- page-out, destroy AND populate on the running object all refused
// x25 -- the ALIAS case: Object_ID 436 shares slot 180 in this core's
//        256-entry model, so a NAME compare would have let an authorized
//        actor clear the running object's descriptor in one instruction.
//        This case cannot exist on the Sail model, where an entry is
//        base(region) + the FULL 24-bit local and names are in bijection
//        with slots -- it is reachable only here.
// x22 -- the refusals did NOT half-apply: 180 re-Binds and its Base still
//        reads back as the compartment, so no refused write reached the table
// x24 -- the over-refusal control: an unrelated live object stays evictable
// x18 -- the saved name pins too, from inside a handler where PCC belongs
//        to no object (x27/x28/x29 are the mcause RECORDS for those three
//        refusals and read 2, not 0x600D)
// x30 -- 0xD09E only once the pin RELEASED after OCRETURN abandoned the
//        frame and the same instruction on the same object then succeeded
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

    repeat (600) begin
      @(posedge clk);
      #1;
      cyc_cnt = cyc_cnt + 1;
    end

    $display("x19(before)=0x%0h x26(A1/A2/A4)=0x%0h x25(alias)=0x%0h x22(nohalf)=0x%0h x24(control)=0x%0h x18(savedpin)=0x%0h x30=0x%0h traps=%0d",
              dut.CPU_Xreg_val_a0[19], dut.CPU_Xreg_val_a0[26], dut.CPU_Xreg_val_a0[25],
              dut.CPU_Xreg_val_a0[22], dut.CPU_Xreg_val_a0[24], dut.CPU_Xreg_val_a0[18], dut.CPU_Xreg_val_a0[30],
              dut.CPU_Xreg_val_a0[20]);

    if (dut.CPU_Xreg_val_a0[30] == 64'hD09E &&
        dut.CPU_Xreg_val_a0[19] == 64'h600D &&
        dut.CPU_Xreg_val_a0[24] == 64'h600D &&
        dut.CPU_Xreg_val_a0[22] == 64'h600D &&
        dut.CPU_Xreg_val_a0[26] == 64'h600D &&
        dut.CPU_Xreg_val_a0[18] == 64'h600D &&
        dut.CPU_Xreg_val_a0[29] == 64'h2 &&
        dut.CPU_Xreg_val_a0[25] == 64'h2) begin
      $display("\n*** TEST PASSED *** (executing-object pin: all four eviction paths refuse the running object, an aliasing Object_ID is refused too, an unrelated object stays evictable, and the pin releases when the frame is abandoned)");
    end else begin
      $display("\n*** TEST FAILED ***");
    end

    $finish;
  end
endmodule
