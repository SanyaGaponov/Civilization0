// tb_buttons.sv - checks debouncing: a bouncy press must give exactly ONE pulse,
// a bouncy release none, and a short glitch nothing at all.
`timescale 1ns/1ps

// Testbench style: blocking "=" in processes is intentional.
/* verilator lint_off BLKSEQ */
module tb_buttons;

  localparam int CNT_W = 4;                 // debounce = 2^4 = 16 clocks

  logic clk, rst;
  logic raw;
  logic press;
  int   pulses, errors;

  initial begin
    clk = 1'b0; rst = 1'b1; raw = 1'b0; pulses = 0; errors = 0;
  end
  always #5 clk = ~clk;

  buttons #(.N(1), .CNT_W(CNT_W)) dut (.clk(clk), .rst(rst), .raw(raw), .press(press));

  always @(posedge clk) if (press) pulses++;

  // Toggle the input quickly n times (contact bounce), then settle at 'level'.
  task automatic bounce(input int n, input logic level);
    for (int i = 0; i < n; i++) begin
      raw = ~raw;
      repeat (1 + (i % 5)) @(negedge clk);   // 1..5 clocks between bounces
    end
    raw = level;
  endtask

  task automatic expect_pulses(input int n, input string what);
    if (pulses != n) begin
      errors++;
      $display("ERROR: %s: %0d pulses, expected %0d", what, pulses, n);
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;

    // 1. bouncy press, then held: exactly one pulse
    bounce(9, 1'b1);
    repeat (100) @(negedge clk);
    expect_pulses(1, "bouncy press");

    // 2. bouncy release: no new pulse
    bounce(7, 1'b0);
    repeat (100) @(negedge clk);
    expect_pulses(1, "bouncy release");

    // 3. glitch shorter than the debounce time: ignored
    raw = 1'b1; repeat (8) @(negedge clk); raw = 1'b0;
    repeat (100) @(negedge clk);
    expect_pulses(1, "short glitch");

    // 4. three clean presses: three pulses
    repeat (3) begin
      raw = 1'b1; repeat (40) @(negedge clk);
      raw = 1'b0; repeat (40) @(negedge clk);
    end
    expect_pulses(4, "three clean presses");

    if (errors == 0) $display("PASS: tb_buttons (bounce, release, glitch, repeated presses)");
    else             $display("FAIL: tb_buttons, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
