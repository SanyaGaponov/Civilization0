// Pixel colour (combinational): terrain background, city/unit/cursor on top.
module drawcon
  import game_pkg::*;
(
  // current pixel, from vga_out
  input  logic [10:0]           draw_x,      // 0..1279
  input  logic [9:0]            draw_y,      // 0..799
  // terrain map (draw read of terrain_memory)
  output logic [MAP_ADDR_W-1:0] map_addr,
  input  logic [TERRAIN_W-1:0]  map_data,
  // game state, from game_ctrl
  input  tile_x_t               cursor_x,
  input  tile_y_t               cursor_y,
  input  player_t               cur_player,
  input  logic                  sel_valid,
  input  logic [UNIT_IDX_W-1:0] sel_idx,
  input  unit_t [MAX_UNITS-1:0] units,
  input  logic                  blink,       // toggles a few times per second
  // colour of this pixel, to vga_out
  output logic [3:0]            r,
  output logic [3:0]            g,
  output logic [3:0]            b
);

  localparam logic [11:0] OUTLINE = 12'h111;   // near-black, non-zero
  localparam logic [11:0] WHITE   = 12'hFFF;

  // ---- which tile, and which pixel inside it --------------------------------
  tile_x_t tile_x;
  tile_y_t tile_y;
  logic [TILE_LOG2-1:0] px, py;                       // 0..31 inside the tile
  assign tile_x   = draw_x[TILE_LOG2 +: MAP_W_LOG2];   // draw_x[10:5]
  assign tile_y   = draw_y[TILE_LOG2 +: MAP_H_LOG2];   // draw_y[9:5]
  assign px       = draw_x[TILE_LOG2-1:0];             // draw_x[4:0]
  assign py       = draw_y[TILE_LOG2-1:0];
  assign map_addr = {tile_y, tile_x};

  // ---- background: terrain ---------------------------------------------------
  logic [3:0] bg_r, bg_g, bg_b;
  assign {bg_r, bg_g, bg_b} = terrain_color(map_data);

  // ---- what stands on this tile ---------------------------------------------
  logic [UNIT_IDX_W:0]   unit_here;                   // {found, index}
  logic [UNIT_IDX_W-1:0] ui;
  logic city0_here, city1_here, cursor_here;
  assign unit_here   = find_unit(units, tile_x, tile_y);
  assign ui          = unit_here[UNIT_IDX_W-1:0];
  assign city0_here  = (tile_x == CITY0_X) && (tile_y == CITY0_Y);
  assign city1_here  = (tile_x == CITY1_X) && (tile_y == CITY1_Y);
  assign cursor_here = (tile_x == cursor_x) && (tile_y == cursor_y);

  // ---- shapes (comparisons on the pixel position inside the tile) ------------
  // Triangle: apex at the top centre (row 5), base at row 26, 20 px wide.
  logic [TILE_LOG2-1:0] dx, hw;
  logic tri_in, tri_edge;
  always_comb begin
    dx       = px[4] ? px - 5'd16 : 5'd15 - px;   // distance from the centre line
    hw       = (py - 5'd5) >> 1;                   // half-width grows downwards
    tri_in   = (py >= 5'd5) && (py <= 5'd26) && (dx <= hw);
    tri_edge = tri_in && ((py >= 5'd25) || (dx >= hw) || (dx + 5'd1 == hw));
  end

  // City: square from 5 to 26, 2-px border, white 6x6 centre.
  logic city_in, city_border, city_centre;
  assign city_in     = (px >= 5'd5)  && (px <= 5'd26) && (py >= 5'd5)  && (py <= 5'd26);
  assign city_border = city_in && (px <= 5'd6 || px >= 5'd25 || py <= 5'd6 || py >= 5'd25);
  assign city_centre = (px >= 5'd13) && (px <= 5'd18) && (py >= 5'd13) && (py <= 5'd18);

  // Cursor: 2-px frame at the tile edges.
  logic cursor_frame;
  assign cursor_frame = (px <= 5'd1) || (px >= 5'd30) || (py <= 5'd1) || (py >= 5'd30);

  function automatic logic [11:0] half(input logic [11:0] c);
    return (c >> 1) & 12'h777;   // halve each 4-bit channel
  endfunction

  // ---- foreground: city, unit, cursor (0 = nothing here) ---------------------
  logic [3:0]  blk_r, blk_g, blk_b;
  logic [11:0] unit_fill;
  always_comb begin
    {blk_r, blk_g, blk_b} = 12'h000;
    // city
    if ((city0_here || city1_here) && city_in)
      {blk_r, blk_g, blk_b} = city_border ? OUTLINE :
                              city_centre ? WHITE   : player_color(city1_here);
    // unit (drawn over the city if one stands there)
    unit_fill = player_color(units[ui].owner);
    if (units[ui].owner == cur_player && units[ui].moves == '0) unit_fill = half(unit_fill);
    if (sel_valid && sel_idx == ui && blink)                     unit_fill = WHITE;
    if (unit_here[UNIT_IDX_W] && tri_in)
      {blk_r, blk_g, blk_b} = tri_edge ? OUTLINE : unit_fill;
    // cursor (on top of everything)
    if (cursor_here && cursor_frame)
      {blk_r, blk_g, blk_b} = player_color(cur_player);
  end

  // ---- combine: foreground wins where it is non-zero ------------------------
  always_comb begin
    if ({blk_r, blk_g, blk_b} != 12'h000) {r, g, b} = {blk_r, blk_g, blk_b};
    else                                  {r, g, b} = {bg_r, bg_g, bg_b};
  end

endmodule
