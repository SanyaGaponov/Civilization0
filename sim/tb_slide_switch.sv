// Testbench: slide switch (bouncing flips, no pulse at reset).
`timescale 1ns/1ps

// Blocking "=" in processes is intentional here.
/* verilator lint_off BLKSEQ */
module tb_slide_switch;

  localparam int LOOK_BITS = 5;             // look every 32 clocks

  logic clk, rst;
  logic switch_signal;
  logic flipped;
  int   pulses, errors, width;

  initial begin
    clk = 1'b0; rst = 1'b1; switch_signal = 1'b1; pulses = 0; errors = 0; width = 0;
  end
  always #5 clk = ~clk;

  slide_switch #(.LOOK_BITS(LOOK_BITS)) dut (.clk(clk), .rst(rst), .switch_signal(switch_signal),
                                             .flipped(flipped));

  // Count pulses; each must last one clock
  always @(posedge clk) begin
    if (flipped) begin
      width++;
      if (width == 1) pulses++;
      if (width == 2) begin
        errors++;
        $display("ERROR: flip pulse longer than one clock");
      end
    end else begin
      width = 0;
    end
  end

  // Bounce: toggle n times quickly (under 32 clocks), then settle at 'level'
  task automatic bounce(input int n, input logic level);
    for (int i = 0; i < n; i++) begin
      switch_signal = ~switch_signal;
      repeat (1 + (i % 5)) @(negedge clk);   // 1..5 clocks apart
    end
    switch_signal = level;
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

    // 1. switch already ON at reset: no pulse
    repeat (200) @(negedge clk);
    expect_pulses(0, "switch on at reset");

    // 2. bouncy flip off: exactly one pulse
    bounce(9, 1'b0);
    repeat (200) @(negedge clk);
    expect_pulses(1, "bouncy flip off");

    // 3. bouncy flip on: one more pulse
    bounce(7, 1'b1);
    repeat (200) @(negedge clk);
    expect_pulses(2, "bouncy flip on");

    // 4. switch left alone: nothing
    repeat (300) @(negedge clk);
    expect_pulses(2, "no flip");

    if (errors == 0) $display("PASS: tb_slide_switch (bouncing flips, no pulse at reset)");
    else             $display("FAIL: tb_slide_switch, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
