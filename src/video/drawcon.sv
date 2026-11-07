// Pixel colour (combinational): terrain background, city/unit/cursor on top.
module drawcon
  import game_pkg::*;
(
  // current pixel, from vga_out
  input  logic [10:0]                draw_x,      // 0..1279
  input  logic [9:0]                 draw_y,      // 0..799
  // terrain map (draw read of terrain_memory)
  output logic [MAP_ADDR_BITS-1:0]   tile_terrain_addr,
  input  logic [TERRAIN_BITS-1:0]    tile_terrain,
  // game state, from game_ctrl
  input  tile_x_t                    cursor_x,
  input  tile_y_t                    cursor_y,
  input  player_t                    current_player,
  input  logic                       unit_selected,
  input  logic [UNIT_INDEX_BITS-1:0] selected_unit,
  input  unit_t [MAX_UNITS-1:0]      unit_table,
  input  logic                       blink,       // toggles a few times per second
  // colour of this pixel, to vga_out
  output logic [3:0]                 r,
  output logic [3:0]                 g,
  output logic [3:0]                 b
);

  localparam logic [11:0] OUTLINE = 12'h111;   // near-black, non-zero
  localparam logic [11:0] WHITE   = 12'hFFF;
  localparam logic [11:0] HP_LEFT = 12'h0F0;   // bright green: hit points the unit still has
  localparam logic [11:0] HP_LOST = 12'h800;   // dark red: hit points already lost

  // ---- which tile, and which pixel inside it --------------------------------
  tile_x_t tile_x;
  tile_y_t tile_y;
  logic [TILE_BITS-1:0] x_in_tile, y_in_tile;            // 0..31 inside the tile
  assign tile_x            = draw_x[TILE_BITS +: MAP_X_BITS];   // draw_x[10:5]
  assign tile_y            = draw_y[TILE_BITS +: MAP_Y_BITS];   // draw_y[9:5]
  assign x_in_tile         = draw_x[TILE_BITS-1:0];             // draw_x[4:0]
  assign y_in_tile         = draw_y[TILE_BITS-1:0];
  assign tile_terrain_addr = {tile_y, tile_x};

  // ---- background: terrain ---------------------------------------------------
  logic [3:0] bg_r, bg_g, bg_b;
  assign {bg_r, bg_g, bg_b} = terrain_color(tile_terrain);

  // ---- what stands on this tile ---------------------------------------------
  logic [UNIT_INDEX_BITS:0]   unit_on_tile;              // {found, index}
  logic [UNIT_INDEX_BITS-1:0] unit_index;
  logic city_p1_here, city_p2_here, cursor_here;
  assign unit_on_tile = find_unit(unit_table, tile_x, tile_y);
  assign unit_index   = unit_on_tile[UNIT_INDEX_BITS-1:0];
  assign city_p1_here = (tile_x == CITY_P1_X) && (tile_y == CITY_P1_Y);
  assign city_p2_here = (tile_x == CITY_P2_X) && (tile_y == CITY_P2_Y);
  assign cursor_here  = (tile_x == cursor_x) && (tile_y == cursor_y);

  // ---- shapes (comparisons on the pixel position inside the tile) ------------
  // Triangle: apex at the top centre (row 5), base at row 26, 22 px wide.
  logic [TILE_BITS-1:0] dist_from_center, half_width;
  logic in_triangle, on_triangle_edge;
  always_comb begin
    dist_from_center = x_in_tile[4] ? x_in_tile - 5'd16 : 5'd15 - x_in_tile;
    half_width       = (y_in_tile - 5'd5) >> 1;   // grows downwards
    in_triangle      = (y_in_tile >= 5'd5) && (y_in_tile <= 5'd26) &&
                       (dist_from_center <= half_width);
    on_triangle_edge = in_triangle && ((y_in_tile >= 5'd25) ||
                                       (dist_from_center >= half_width) ||
                                       (dist_from_center + 5'd1 == half_width));
  end

  // HP bar under the triangle: rows 28-29, x 6..25 = 10 segments of 2 px.
  logic                 on_hp_bar;
  logic [HP_BITS-1:0]   hp_segment;           // 0..9: which segment this pixel belongs to
  assign on_hp_bar  = (y_in_tile >= 5'd28) && (y_in_tile <= 5'd29) &&
                      (x_in_tile >= 5'd6)  && (x_in_tile <= 5'd25);
  assign hp_segment = HP_BITS'((x_in_tile - 5'd6) >> 1);

  // City: square from 5 to 26, 2-px border, white 6x6 centre.
  logic in_city, on_city_border, in_city_center;
  assign in_city        = (x_in_tile >= 5'd5)  && (x_in_tile <= 5'd26) &&
                          (y_in_tile >= 5'd5)  && (y_in_tile <= 5'd26);
  assign on_city_border = in_city && (x_in_tile <= 5'd6 || x_in_tile >= 5'd25 ||
                                      y_in_tile <= 5'd6 || y_in_tile >= 5'd25);
  assign in_city_center = (x_in_tile >= 5'd13) && (x_in_tile <= 5'd18) &&
                          (y_in_tile >= 5'd13) && (y_in_tile <= 5'd18);

  // Cursor: 2-px frame at the tile edges.
  logic on_cursor_frame;
  assign on_cursor_frame = (x_in_tile <= 5'd1) || (x_in_tile >= 5'd30) ||
                           (y_in_tile <= 5'd1) || (y_in_tile >= 5'd30);

  function automatic logic [11:0] dim(input logic [11:0] c);
    return (c >> 1) & 12'h777;   // halve each 4-bit channel
  endfunction

  // ---- foreground: city, unit + HP bar, cursor (0 = nothing here) ---------------------
  logic [3:0]  blk_r, blk_g, blk_b;
  logic [11:0] unit_color;
  always_comb begin
    {blk_r, blk_g, blk_b} = 12'h000;
    // city
    if ((city_p1_here || city_p2_here) && in_city)
      {blk_r, blk_g, blk_b} = on_city_border ? OUTLINE :
                              in_city_center ? WHITE   : player_color(city_p2_here);
    // unit (drawn over the city if one stands there)
    unit_color = player_color(unit_table[unit_index].owner);
    if (unit_table[unit_index].owner == current_player && unit_table[unit_index].moves_left == '0)
      unit_color = dim(unit_color);             // own unit with no moves left
    if (unit_selected && selected_unit == unit_index && blink)
      unit_color = WHITE;                       // selected unit blinks
    if (unit_on_tile[UNIT_INDEX_BITS] && in_triangle)
      {blk_r, blk_g, blk_b} = on_triangle_edge ? OUTLINE : unit_color;
    // HP bar: segment k is green if the unit has more than k hit points
    if (unit_on_tile[UNIT_INDEX_BITS] && on_hp_bar)
      {blk_r, blk_g, blk_b} = (hp_segment < unit_table[unit_index].hp) ? HP_LEFT : HP_LOST;
    // cursor (on top of everything)
    if (cursor_here && on_cursor_frame)
      {blk_r, blk_g, blk_b} = player_color(current_player);
  end

  // ---- combine: foreground wins where it is non-zero ------------------------
  always_comb begin
    if ({blk_r, blk_g, blk_b} != 12'h000) {r, g, b} = {blk_r, blk_g, blk_b};
    else                                  {r, g, b} = {bg_r, bg_g, bg_b};
  end

endmodule
