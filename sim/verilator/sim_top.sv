// Simulation wrapper: game_top plus constants for sim_frame.cpp.
module sim_top
  import game_pkg::*;
#(
  parameter string MAP_FILE    = "map0.mem",
  parameter string SPRITE_FILE = "sprites.mem"
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
  output logic [7:0]  p_play_w, p_play_h,
  output logic [15:0] p_map_left, p_map_top
);

  /* verilator lint_off PINCONNECTEMPTY */
  game_top #(.MAP_FILE(MAP_FILE), .SPRITE_FILE(SPRITE_FILE)) dut (
    .clk       (clk),
    .CPU_RESETN(rst_n),
    .BTNC(btn[0]), .BTNU(btn[1]), .BTND(btn[2]), .BTNL(btn[3]), .BTNR(btn[4]),
    .pix_r(r), .pix_g(g), .pix_b(b),
    .hsync(hs), .vsync(vs),
    .LED(),
    .CA(), .CB(), .CC(), .CD(), .CE(), .CF(), .CG(), .DP(), .AN()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Timing, as in vga_out
  assign p_h_sync   = 16'd136;
  assign p_h_bp     = 16'd200;
  assign p_h_active = 16'd1280;
  assign p_h_total  = 16'd1680;
  assign p_v_sync   = 16'd3;
  assign p_v_bp     = 16'd24;
  assign p_v_active = 16'd800;
  assign p_v_total  = 16'd828;
  assign p_h_pol    = 1'b0;      // hsync active low
  assign p_v_pol    = 1'b1;      // vsync active high
  assign p_tcol0    = terrain_color(T_OCEAN);
  assign p_tcol1    = terrain_color(T_GRASS);
  assign p_tcol2    = terrain_color(T_PLAINS);
  assign p_tcol3    = terrain_color(T_FOREST);
  assign p_tcol4    = terrain_color(T_HILLS);
  assign p_tcol5    = terrain_color(T_MOUNTAIN);
  assign p_pcol0    = player_color(1'b0);
  assign p_pcol1    = player_color(1'b1);
  assign p_play_w   = 8'(PLAY_TILES_X);
  assign p_play_h   = 8'(PLAY_TILES_Y);
  assign p_map_left = 16'(MAP_LEFT);
  assign p_map_top  = 16'(MAP_TOP);

endmodule
