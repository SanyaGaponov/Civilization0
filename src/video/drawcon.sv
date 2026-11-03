// drawcon.sv - decides the colour of each pixel (slide 11 "drawcon").
//
// Pipeline (one row = one clock):
//   stage 0  (inputs from vga_out)   x, y  ->  map_addr = {y>>5, x>>5}
//   stage 1  terrain ROM returns the tile type   (ROM latency = 1 clock)
//   stage 2  tile type -> colour, registered to the output pins
//
// The colour therefore appears 2 clocks after x/y. hsync, vsync and de are
// delayed by the same 2 clocks, otherwise the picture would be shifted
// sideways relative to the sync pulses (see course README "timing issues").
//
// For now every tile is a plain colour. Later, a tile-graphics ROM indexed by
// {terrain, y[4:0], x[4:0]} will replace terrain_color() in stage 2.
module drawcon
  import game_pkg::*;
#(
  parameter bit GRID = 1'b0          // 1 = darken the first row/column of each tile
)(
  input  logic                  clk,
  // from vga_out (stage 0)
  input  logic                  hsync_in,
  input  logic                  vsync_in,
  input  logic                  de_in,
  input  logic [HCNT_W-1:0]     x,
  input  logic [VCNT_W-1:0]     y,
  // to / from the terrain map
  output logic [MAP_ADDR_W-1:0] map_addr,
  input  logic [TERRAIN_W-1:0]  map_data,
  // to the VGA pins (stage 2)
  output logic [3:0]            vga_r,
  output logic [3:0]            vga_g,
  output logic [3:0]            vga_b,
  output logic                  vga_hs,
  output logic                  vga_vs
);

  // ---- stage 0: tile coordinates -> map address (pure wiring, no maths) ----
  logic [MAP_W_LOG2-1:0] tile_x;
  logic [MAP_H_LOG2-1:0] tile_y;
  assign tile_x   = x[TILE_LOG2 +: MAP_W_LOG2];   // x[10:5]
  assign tile_y   = y[TILE_LOG2 +: MAP_H_LOG2];   // y[9:5]
  assign map_addr = {tile_y, tile_x};

  // ---- stage 1: wait for the ROM; delay the control signals by 1 ----------
  logic hs1, vs1, de1, edge1;
  always_ff @(posedge clk) begin
    hs1   <= hsync_in;
    vs1   <= vsync_in;
    de1   <= de_in;
    edge1 <= (x[TILE_LOG2-1:0] == '0) || (y[TILE_LOG2-1:0] == '0);
  end

  // ---- stage 2: colour lookup, registered outputs --------------------------
  function automatic logic [11:0] terrain_color(input logic [TERRAIN_W-1:0] t);
    case (t)
      T_OCEAN:    return 12'h15A;   // blue
      T_GRASS:    return 12'h4A3;   // green
      T_PLAINS:   return 12'hBB5;   // yellow-green
      T_FOREST:   return 12'h262;   // dark green
      T_HILLS:    return 12'h864;   // brown
      T_MOUNTAIN: return 12'hAAA;   // grey
      default:    return 12'hF0F;   // magenta = bad map data (debug aid)
    endcase
  endfunction

  logic [11:0] rgb;
  always_comb begin
    rgb = terrain_color(map_data);
    if (GRID && edge1) rgb = {1'b0, rgb[11:9], 1'b0, rgb[7:5], 1'b0, rgb[3:1]}; // half brightness
  end

  always_ff @(posedge clk) begin
    vga_hs <= hs1;
    vga_vs <= vs1;
    // Outside the visible area the colour MUST be black, or the monitor
    // mis-detects the black level.
    {vga_r, vga_g, vga_b} <= de1 ? rgb : 12'h000;
  end

endmodule
