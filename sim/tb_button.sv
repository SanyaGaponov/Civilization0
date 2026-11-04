// Testbench: one button (bouncing, release, repeated presses).
`timescale 1ns/1ps

// Testbench style: blocking "=" in processes is intentional.
/* verilator lint_off BLKSEQ */
module tb_button;

  localparam int SLOW_W = 5;                // look every 2^5 = 32 clocks

  logic clk, rst;
  logic pressed_signal;
  logic pressed_finally;
  int   pulses, errors, width;

  initial begin
    clk = 1'b0; rst = 1'b1; pressed_signal = 1'b0; pulses = 0; errors = 0; width = 0;
  end
  always #5 clk = ~clk;

  button #(.SLOW_W(SLOW_W)) dut (.clk(clk), .rst(rst), .pressed_signal(pressed_signal), .pressed_finally(pressed_finally));

  // count pulses and check that each one lasts exactly one clock
  always @(posedge clk) begin
    if (pressed_finally) begin
      width++;
      if (width == 1) pulses++;
      if (width == 2) begin
        errors++;
        $display("ERROR: press pulse longer than one clock");
      end
    end else begin
      width = 0;
    end
  end

  // Toggle the input quickly n times (contact bounce), then settle at 'level'.
  // Total bounce time stays below 32 clocks, like a real button vs. 12.6 ms.
  task automatic bounce(input int n, input logic level);
    for (int i = 0; i < n; i++) begin
      pressed_signal = ~pressed_signal;
      repeat (1 + (i % 5)) @(negedge clk);   // 1..5 clocks between bounces
    end
    pressed_signal = level;
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
    repeat (200) @(negedge clk);
    expect_pulses(1, "bouncy press, held");

    // 2. bouncy release: no new pulse
    bounce(7, 1'b0);
    repeat (200) @(negedge clk);
    expect_pulses(1, "bouncy release");

    // 3. three clean presses: three pulses
    repeat (3) begin
      pressed_signal = 1'b1; repeat (80) @(negedge clk);
      pressed_signal = 1'b0; repeat (80) @(negedge clk);
    end
    expect_pulses(4, "three clean presses");

    if (errors == 0) $display("PASS: tb_button (bounce, release, repeated presses)");
    else             $display("FAIL: tb_button, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
