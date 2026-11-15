// Testbench: multidigit (digit order, anodes, blanking with en).
`timescale 1ns/1ps

// Blocking "=" in processes is intentional here.
/* verilator lint_off BLKSEQ */
module tb_multidigit;

  logic       clk, rst, tick;
  logic [3:0] digs [8];                 // the eight values we feed in
  logic [7:0] en;
  logic       a, b, c, d, e, f, g;
  logic [7:0] an;
  int         errors;

  initial begin
    clk = 1'b0; rst = 1'b1; tick = 1'b1; en = 8'hFF; errors = 0;
    for (int i = 0; i < 8; i++) digs[i] = 4'(i + 1);   // 1..8, all different
  end
  always #5 clk = ~clk;

  multidigit dut (
    .clk (clk),
    .rst (rst),
    .tick(tick),
    .dig0(digs[0]), .dig1(digs[1]), .dig2(digs[2]), .dig3(digs[3]),
    .dig4(digs[4]), .dig5(digs[5]), .dig6(digs[6]), .dig7(digs[7]),
    .en  (en),
    .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g),
    .an(an)
  );

  // Reference decoder: what the segments should be for the digit we expect
  logic [3:0] ref_num;
  logic       ra, rb, rc, rd, re, rf, rg;
  sevenseg ref_seg (.num(ref_num), .a(ra), .b(rb), .c(rc), .d(rd), .e(re), .f(rf), .g(rg));

  // Check the digit the design should be driving in this clock cycle
  task automatic check_digit(input int k);
    logic [7:0] want_an;
    want_an = en[k] ? ~(8'd1 << k) : 8'hFF;
    ref_num = digs[k];
    #1;
    if (an !== want_an) begin
      errors++;
      $display("ERROR: digit %0d: an=%b, expected %b", k, an, want_an);
    end
    if (en[k] && ({a, b, c, d, e, f, g} !== {ra, rb, rc, rd, re, rf, rg})) begin
      errors++;
      $display("ERROR: digit %0d (value %0h): segments %b, expected %b",
               k, digs[k], {a, b, c, d, e, f, g}, {ra, rb, rc, rd, re, rf, rg});
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;                         // cnt is 0 now: digit 0 is driven

    // 1. all digits shown: two full turns through the display, in order
    for (int i = 0; i < 16; i++) begin
      check_digit(i % 8);
      @(negedge clk);
    end

    // 2. tick low: the design must stay on the digit it is showing
    tick = 1'b0;
    repeat (3) begin
      check_digit(0);                   // 16 steps done, so back at digit 0
      @(negedge clk);
    end
    tick = 1'b1;

    // 3. en: only digits 0 and 1 light up, the rest keep all anodes off
    en = 8'b0000_0011;
    for (int i = 0; i < 8; i++) begin
      check_digit(i);
      @(negedge clk);
    end

    if (errors == 0) $display("PASS: tb_multidigit (digit order, anodes, blanking)");
    else             $display("FAIL: tb_multidigit, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
