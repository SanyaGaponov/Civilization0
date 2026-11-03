// tb_vga_out.sv - self-checking testbench for vga_out.
// Runs in Vivado's simulator (set as simulation top) or in Verilator (`make tb`).
// Checks, for 2 full frames:
//   - hsync period = H_TOTAL clocks, pulse width = H_SYNC clocks
//   - vsync period = H_TOTAL*V_TOTAL clocks, pulse width = V_SYNC lines
//   - each visible line has exactly H_ACTIVE pixels, x counts 0..H_ACTIVE-1
//   - each frame has exactly V_ACTIVE visible lines, y counts 0..V_ACTIVE-1
//   - frame_end pulses exactly once per frame
`timescale 1ns/1ps
// Testbench style: blocking "=" inside the sampling process is intentional.
/* verilator lint_off BLKSEQ */
module tb_vga_out;
  import game_pkg::*;

  // Start values are set in initial blocks, not in the declarations
  // (newer Verilator warns about declaration initializers on variables
  // that processes also write, warning PROCASSINIT).
  logic clk, rst;
  initial begin
    clk = 1'b0;
    rst = 1'b1;
  end
  always #5 clk = ~clk;

  logic              hsync, vsync, de, frame_end;
  logic [HCNT_W-1:0] x;
  logic [VCNT_W-1:0] y;

  vga_out dut (.clk(clk), .rst(rst), .hsync(hsync), .vsync(vsync), .de(de),
               .x(x), .y(y), .frame_end(frame_end));

  int cyc, errors, frames;
  int last_hs_edge, last_vs_edge;
  int hs_width, vs_width;
  int de_run, active_lines, frame_ends;
  logic hsync_q, vsync_q, de_q;
  initial begin
    cyc = 0; errors = 0; frames = 0;
    last_hs_edge = -1; last_vs_edge = -1;
    hs_width = 0; vs_width = 0;
    de_run = 0; active_lines = 0; frame_ends = 0;
    hsync_q = 1'b0; vsync_q = 1'b0; de_q = 1'b0;
  end

  task automatic check(input bit ok, input string msg);
    if (!ok) begin
      errors++;
      if (errors <= 10) $display("ERROR @%0d: %s", cyc, msg);
    end
  endtask

  // Sample on the falling edge, when all DUT outputs are stable.
  always @(negedge clk) begin
    if (!rst) begin
      cyc++;

      // ---- hsync ----
      if (hsync == H_POL) hs_width++;
      if (hsync == H_POL && hsync_q != H_POL) begin            // leading edge
        if (last_hs_edge >= 0)
          check(cyc - last_hs_edge == H_TOTAL, $sformatf("hsync period %0d != %0d", cyc - last_hs_edge, H_TOTAL));
        last_hs_edge = cyc;
      end
      if (hsync != H_POL && hsync_q == H_POL) begin            // trailing edge
        check(hs_width == H_SYNC, $sformatf("hsync width %0d != %0d", hs_width, H_SYNC));
        hs_width = 0;
      end

      // ---- visible pixels ----
      if (de) begin
        check(int'(x) == de_run,       $sformatf("x=%0d, expected %0d", x, de_run));
        check(int'(y) == active_lines, $sformatf("y=%0d, expected %0d", y, active_lines));
        de_run++;
      end
      if (!de && de_q) begin                                   // end of a visible line
        check(de_run == H_ACTIVE, $sformatf("visible pixels per line %0d != %0d", de_run, H_ACTIVE));
        de_run = 0;
        active_lines++;
      end
      if (frame_end) frame_ends++;

      // ---- vsync ----
      if (vsync == V_POL) vs_width++;
      if (vsync != V_POL && vsync_q == V_POL) begin
        check(vs_width == V_SYNC * H_TOTAL, $sformatf("vsync width %0d clocks != %0d", vs_width, V_SYNC * H_TOTAL));
        vs_width = 0;
      end
      if (vsync == V_POL && vsync_q != V_POL) begin            // new frame
        if (last_vs_edge >= 0) begin
          check(cyc - last_vs_edge == H_TOTAL * V_TOTAL,
                $sformatf("frame period %0d != %0d", cyc - last_vs_edge, H_TOTAL * V_TOTAL));
          check(active_lines == V_ACTIVE, $sformatf("visible lines %0d != %0d", active_lines, V_ACTIVE));
          check(frame_ends == 1, $sformatf("frame_end pulsed %0d times", frame_ends));
          frames++;
        end
        last_vs_edge = cyc;
        active_lines = 0;
        frame_ends   = 0;
      end

      hsync_q = hsync;
      vsync_q = vsync;
      de_q    = de;
    end
  end

  initial begin
    $display("tb_vga_out: %0dx%0d, total %0dx%0d", H_ACTIVE, V_ACTIVE, H_TOTAL, V_TOTAL);
    repeat (4) @(posedge clk);
    rst = 1'b0;
    wait (frames == 2);
    if (errors == 0) $display("PASS: 2 frames checked, no errors");
    else             $display("FAIL: %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
