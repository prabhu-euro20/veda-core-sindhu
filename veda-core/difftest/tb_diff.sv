`timescale 1ns/1ps
// GENERIC DIFFERENTIAL TESTBENCH.
// Dumps the signature region 0x80070000..+SIG_BYTES as 32-bit little-endian
// words, one per line, lowercase hex -- byte-for-byte the format
// sail_riscv_sim's own --test-signature emits, so the two can be diffed
// directly. It asserts NOTHING: divergence is the finding, not failure.
module tb;
  localparam int unsigned SIG_BASE  = 32'h8007_0000;
  localparam int unsigned SIG_BYTES = 768;
  localparam int unsigned RUN_CYC   = 3000;
  logic clk = 0; logic reset; logic [31:0] cyc_cnt = 0; wire passed, failed;
  top dut(.clk(clk), .reset(reset), .cyc_cnt(cyc_cnt), .passed(passed), .failed(failed));
  always #5 clk = ~clk;
  integer fh; integer w; logic [31:0] word;
  string sigfile;
  initial begin
    if (!$value$plusargs("sigout=%s", sigfile)) sigfile = "rtl.sig";
    reset = 1; repeat (2) @(posedge clk); reset = 0;
    repeat (RUN_CYC) begin @(posedge clk); #1; cyc_cnt = cyc_cnt + 1; end
    fh = $fopen(sigfile, "w");
    for (w = 0; w < SIG_BYTES/4; w = w + 1) begin
      word = {dut.elfmem[SIG_BASE + w*4 + 3], dut.elfmem[SIG_BASE + w*4 + 2],
              dut.elfmem[SIG_BASE + w*4 + 1], dut.elfmem[SIG_BASE + w*4 + 0]};
      $fdisplay(fh, "%08x", word);
    end
    $fclose(fh);
    $display("RTL signature written to %0s", sigfile);
    $finish;
  end
endmodule
