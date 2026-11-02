// vga_out.sv - VGA timing generator (slides 7-8).
//
// Two counters: hcnt counts every pixel clock, vcnt counts once per line.
// Comparators on the counters produce hsync, vsync and the "visible" flag.
// All outputs are registered, so they are aligned with each other and
// arrive 1 clock after the counter value they were computed from.
`default_nettype none

module vga_out
  import game_pkg::*;
(
  input  wire               clk,
  input  wire               rst,
  output logic              hsync,
  output logic              vsync,
  output logic              de,         // data enable: 1 inside the visible area
  output logic [HCNT_W-1:0] x,          // pixel column, valid when de = 1
  output logic [VCNT_W-1:0] y,          // pixel row,    valid when de = 1
  output logic              frame_end   // 1-clock pulse right after the last visible line
);

  localparam int H_START = H_SYNC + H_BP;   // first visible column (336 / 144)
  localparam int V_START = V_SYNC + V_BP;   // first visible line   (27 / 35)

  logic [HCNT_W-1:0] hcnt;
  logic [VCNT_W-1:0] vcnt;

  // --- counters ---------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      hcnt <= '0;
      vcnt <= '0;
    end else if (hcnt == HCNT_W'(H_TOTAL - 1)) begin
      hcnt <= '0;
      vcnt <= (vcnt == VCNT_W'(V_TOTAL - 1)) ? '0 : vcnt + 1'b1;
    end else begin
      hcnt <= hcnt + 1'b1;
    end
  end

  // --- comparators (combinational) -------------------------------------
  logic h_vis, v_vis;
  assign h_vis = (hcnt >= HCNT_W'(H_START)) && (hcnt < HCNT_W'(H_START + H_ACTIVE));
  assign v_vis = (vcnt >= VCNT_W'(V_START)) && (vcnt < VCNT_W'(V_START + V_ACTIVE));

  // --- registered outputs ------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      hsync     <= ~H_POL;
      vsync     <= ~V_POL;
      de        <= 1'b0;
      x         <= '0;
      y         <= '0;
      frame_end <= 1'b0;
    end else begin
      hsync     <= (hcnt < HCNT_W'(H_SYNC)) ? H_POL : ~H_POL;
      vsync     <= (vcnt < VCNT_W'(V_SYNC)) ? V_POL : ~V_POL;
      de        <= h_vis && v_vis;
      x         <= hcnt - HCNT_W'(H_START);   // garbage outside visible area; use de
      y         <= vcnt - VCNT_W'(V_START);
      frame_end <= (hcnt == '0) && (vcnt == VCNT_W'(V_START + V_ACTIVE));
    end
  end

endmodule

`default_nettype wire
