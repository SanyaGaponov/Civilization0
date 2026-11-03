// sim_top.sv - Verilator wrapper around game_top.
// Exposes the timing constants and colours so the C++ "virtual monitor"
// knows where the visible window is and which colours are terrain. It does
// NOT peek inside the design: like a real monitor, it only sees the VGA pins.
// Buttons are debounced over 2^4 clocks here (instead of ~10 ms) so a press
// takes microseconds of simulated time.
module sim_top
  import game_pkg::*;
#(
  parameter string MAP_FILE = "map0.mem"
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic [4:0]  btn,          // {R, L, D, U, C}
  output logic [3:0]  r, g, b,
  output logic        hs, vs,
  output logic [15:0] p_h_sync, p_h_bp, p_h_active, p_h_total,
  output logic [15:0] p_v_sync, p_v_bp, p_v_active, p_v_total,
  output logic        p_h_pol, p_v_pol,
  output logic [11:0] p_tcol0, p_tcol1, p_tcol2, p_tcol3, p_tcol4, p_tcol5,
  output logic [11:0] p_pcol0, p_pcol1,
  output logic [7:0]  p_play_w, p_play_h
);

  /* verilator lint_off PINCONNECTEMPTY */
  game_top #(.MAP_FILE(MAP_FILE), .DEBOUNCE_W(4)) dut (
    .CLK100MHZ (clk),
    .CPU_RESETN(rst_n),
    .BTNC(btn[0]), .BTNU(btn[1]), .BTND(btn[2]), .BTNL(btn[3]), .BTNR(btn[4]),
    .VGA_R(r), .VGA_G(g), .VGA_B(b),
    .VGA_HS(hs), .VGA_VS(vs),
    .LED()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign p_h_sync   = 16'(H_SYNC);
  assign p_h_bp     = 16'(H_BP);
  assign p_h_active = 16'(H_ACTIVE);
  assign p_h_total  = 16'(H_TOTAL);
  assign p_v_sync   = 16'(V_SYNC);
  assign p_v_bp     = 16'(V_BP);
  assign p_v_active = 16'(V_ACTIVE);
  assign p_v_total  = 16'(V_TOTAL);
  assign p_h_pol    = H_POL;
  assign p_v_pol    = V_POL;
  assign p_tcol0    = terrain_color(T_OCEAN);
  assign p_tcol1    = terrain_color(T_GRASS);
  assign p_tcol2    = terrain_color(T_PLAINS);
  assign p_tcol3    = terrain_color(T_FOREST);
  assign p_tcol4    = terrain_color(T_HILLS);
  assign p_tcol5    = terrain_color(T_MOUNTAIN);
  assign p_pcol0    = player_color(1'b0);
  assign p_pcol1    = player_color(1'b1);
  assign p_play_w   = 8'(PLAY_W);
  assign p_play_h   = 8'(PLAY_H);

endmodule
