// Testbench: VGA timing, blanking and pixel coordinates.
`timescale 1ns/1ps

// Testbench style: blocking "=" inside the sampling process is intentional.
/* verilator lint_off BLKSEQ */
module tb_vga_out;

  // Expected screen timing (1280x800 at 60 Hz), written independently of vga_out.
  localparam int H_SYNC = 136, H_ACTIVE = 1280, H_TOTAL = 1680;
  localparam int V_SYNC = 3,   V_ACTIVE = 800,  V_TOTAL = 828;
  localparam logic HS_ON = 1'b0;   // hsync level during its pulse (active low)
  localparam logic VS_ON = 1'b1;   // vsync level during its pulse (active high)

  logic clk, rst;
  initial begin
    clk = 1'b0;
    rst = 1'b1;
  end
  always #5 clk = ~clk;

  localparam logic [3:0] R = 4'hA, G = 4'h5, B = 4'hC;   // test colour

  logic [3:0]        pix_r, pix_g, pix_b;
  logic              hsync, vsync;
  logic [10:0]       curr_x;
  logic [9:0]        curr_y;

  vga_out dut (.clk(clk), .rst(rst), .r(R), .g(G), .b(B),
               .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
               .hsync(hsync), .vsync(vsync), .curr_x(curr_x), .curr_y(curr_y));

  int cyc, errors, frames;
  int last_hs_edge, last_vs_edge;
  int hs_width, vs_width;
  int run, lines;
  logic hsync_q, vsync_q, vis_q;
  bit   first, hs_seen, vs_seen;   // only measure pulses whose start we saw
  initial begin
    first = 1'b1; hs_seen = 1'b0; vs_seen = 1'b0;
    cyc = 0; errors = 0; frames = 0;
    last_hs_edge = -1; last_vs_edge = -1;
    hs_width = 0; vs_width = 0; run = 0; lines = 0;
    hsync_q = ~HS_ON; vsync_q = ~VS_ON; vis_q = 1'b0;
  end

  task automatic check(input bit ok, input string msg);
    if (!ok) begin
      errors++;
      if (errors <= 10) $display("ERROR @%0d: %s", cyc, msg);
    end
  endtask

  logic vis;   // colour is being output
  assign vis = (pix_r != 4'h0) || (pix_g != 4'h0) || (pix_b != 4'h0);

  // Sample on the falling edge, when all DUT outputs are stable.
  always @(negedge clk) begin
    if (!rst && first) begin
      // first sample after reset: take the current levels as "previous",
      // so a pulse that is already running is not mistaken for a new one
      first   = 1'b0;
      hsync_q = hsync;
      vsync_q = vsync;
      vis_q   = vis;
    end else if (!rst) begin
      cyc++;

      // ---- hsync ----
      if (hsync == HS_ON) hs_width++;
      if (hsync == HS_ON && hsync_q != HS_ON) begin            // pulse starts
        hs_seen = 1'b1;
        if (last_hs_edge >= 0)
          check(cyc - last_hs_edge == H_TOTAL, $sformatf("hsync period %0d != %0d", cyc - last_hs_edge, H_TOTAL));
        last_hs_edge = cyc;
      end
      if (hsync != HS_ON && hsync_q == HS_ON) begin            // pulse ends
        if (hs_seen) check(hs_width == H_SYNC, $sformatf("hsync pulse %0d != %0d clocks", hs_width, H_SYNC));
        hs_width = 0;
      end

      // ---- visible pixels ----
      if (vis) begin
        check(pix_r == R && pix_g == G && pix_b == B, "wrong colour on the pins");
        check(int'(curr_x) == run,   $sformatf("curr_x=%0d, expected %0d", curr_x, run));
        check(int'(curr_y) == lines, $sformatf("curr_y=%0d, expected %0d", curr_y, lines));
        run++;
      end
      if (!vis && vis_q) begin                                 // end of a visible line
        check(run == H_ACTIVE, $sformatf("visible pixels per line %0d != %0d", run, H_ACTIVE));
        run = 0;
        lines++;
      end

      // ---- vsync ----
      if (vsync == VS_ON) vs_width++;
      if (vsync != VS_ON && vsync_q == VS_ON) begin
        if (vs_seen) check(vs_width == V_SYNC * H_TOTAL, $sformatf("vsync pulse %0d clocks != %0d", vs_width, V_SYNC * H_TOTAL));
        vs_width = 0;
      end
      if (vsync == VS_ON && vsync_q != VS_ON) begin            // new frame
        vs_seen = 1'b1;
        if (last_vs_edge >= 0) begin
          check(cyc - last_vs_edge == H_TOTAL * V_TOTAL,
                $sformatf("frame period %0d != %0d", cyc - last_vs_edge, H_TOTAL * V_TOTAL));
          check(lines == V_ACTIVE, $sformatf("visible lines %0d != %0d", lines, V_ACTIVE));
          frames++;
        end
        last_vs_edge = cyc;
        lines = 0;
      end

      hsync_q = hsync;
      vsync_q = vsync;
      vis_q   = vis;
    end
  end

  initial begin
    $display("tb_vga_out: %0dx%0d visible, %0dx%0d total", H_ACTIVE, V_ACTIVE, H_TOTAL, V_TOTAL);
    repeat (4) @(posedge clk);
    rst = 1'b0;
    wait (frames == 2);
    if (errors == 0) $display("PASS: tb_vga_out, 2 frames checked");
    else             $display("FAIL: tb_vga_out, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
