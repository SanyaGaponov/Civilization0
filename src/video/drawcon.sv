// Pixel colour: terrain background, city and unit sprites, HP bars and cursor on top.
module drawcon
  import game_pkg::*;
(
  // current pixel, from vga_out
  input  logic [                10:0] draw_x,             // 0..1279
  input  logic [                 9:0] draw_y,             // 0..799
  // terrain lookup
  output logic [   MAP_ADDR_BITS-1:0] tile_terrain_addr,
  input  logic [    TERRAIN_BITS-1:0] tile_terrain,
  // sprite lookups
  output logic [SPRITE_ADDR_BITS-1:0] unit_sprite_addr,
  input  logic [      PIXEL_BITS-1:0] unit_sprite_pixel,
  output logic [SPRITE_ADDR_BITS-1:0] city_sprite_addr,
  input  logic [      PIXEL_BITS-1:0] city_sprite_pixel,
  // game state, from game_ctrl
  input  logic [      MAP_X_BITS-1:0] cursor_x,
  input  logic [      MAP_Y_BITS-1:0] cursor_y,
  input  logic                        current_player,
  input  logic                        unit_selected,
  input  logic [ UNIT_INDEX_BITS-1:0] selected_unit,
  input  unit  [       MAX_UNITS-1:0] unit_table,
  // pixel colour, to vga_out
  output logic [                 3:0] r,
  output logic [                 3:0] g,
  output logic [                 3:0] b
);

  localparam logic [11:0] WHITE = 12'hFFF;
  localparam logic [11:0] HP_LEFT = 12'h0F0;  // green: HP left
  localparam logic [11:0] HP_LOST = 12'h800;  // red: HP lost

  // Map area in the middle of the screen; black around it
  localparam logic [10:0] MAP_RIGHT = 11'(MAP_LEFT + (PLAY_TILES_X << TILE_BITS));
  localparam logic [9:0] MAP_BOTTOM = 10'(MAP_TOP + (PLAY_TILES_Y << TILE_BITS));
  logic on_map;
  logic [9:0] map_x, map_y;  // pixel position inside the map
  assign on_map = (draw_x >= 11'(MAP_LEFT)) && (draw_x < MAP_RIGHT) &&
                  (draw_y >= 10'(MAP_TOP))  && (draw_y < MAP_BOTTOM);
  assign map_x = 10'(draw_x - 11'(MAP_LEFT));
  assign map_y = draw_y - 10'(MAP_TOP);

  // Tile under the pixel, and the pixel's position inside it (0..31)
  logic [MAP_X_BITS-1:0] tile_x;
  logic [MAP_Y_BITS-1:0] tile_y;
  logic [TILE_BITS-1:0] x_in_tile, y_in_tile;
  assign tile_x            = map_x[TILE_BITS+:MAP_X_BITS];  // map_x[9:5]
  assign tile_y            = map_y[TILE_BITS+:MAP_Y_BITS];  // map_y[9:5]
  assign x_in_tile         = map_x[TILE_BITS-1:0];  // map_x[4:0]
  assign y_in_tile         = map_y[TILE_BITS-1:0];
  assign tile_terrain_addr = {tile_y, tile_x};

  // Background: terrain colour
  logic [3:0] bg_r, bg_g, bg_b;
  assign {bg_r, bg_g, bg_b} = terrain_color(tile_terrain);

  // What is on this tile
  logic [  UNIT_INDEX_BITS:0] unit_on_tile;  // {found, index}
  logic [UNIT_INDEX_BITS-1:0] unit_index;
  logic city_p1_here, city_p2_here, cursor_here;
  assign unit_on_tile = find_unit(unit_table, tile_x, tile_y);
  assign unit_index   = unit_on_tile[UNIT_INDEX_BITS-1:0];
  assign city_p1_here = (tile_x == CITY_P1_X) && (tile_y == CITY_P1_Y);
  assign city_p2_here = (tile_x == CITY_P2_X) && (tile_y == CITY_P2_Y);
  assign cursor_here  = (tile_x == cursor_x) && (tile_y == cursor_y);

  // Sprite pixel: 16x16 sprite drawn 2x, so drop the lowest bit of the position
  logic [SPRITE_BITS-1:0] sprite_x, sprite_y;
  assign sprite_x         = x_in_tile[TILE_BITS-1-:SPRITE_BITS];  // x_in_tile[4:1]
  assign sprite_y         = y_in_tile[TILE_BITS-1-:SPRITE_BITS];
  assign unit_sprite_addr = {unit_table[unit_index].unit_type, sprite_y, sprite_x};
  assign city_sprite_addr = {SPRITE_CITY, sprite_y, sprite_x};

  // HP bar: rows 28-29, up to 10 segments of 2 px
  logic               on_hp_bar;
  logic [HP_BITS-1:0] hp_segment;  // 0..9
  assign on_hp_bar  = (y_in_tile >= 5'd28) && (y_in_tile <= 5'd29) &&
                      (x_in_tile >= 5'd6)  && (x_in_tile <= 5'd25);
  assign hp_segment = HP_BITS'((x_in_tile - 5'd6) >> 1);

  // Cursor: 2-px frame at the tile edge
  logic on_cursor_frame;
  assign on_cursor_frame = (x_in_tile <= 5'd1) || (x_in_tile >= 5'd30) ||
                           (y_in_tile <= 5'd1) || (y_in_tile >= 5'd30);

  // Half brightness
  function automatic logic [11:0] dim(input logic [11:0] c);
    return (c >> 1) & 12'h777;
  endfunction

  // Foreground, later layers on top (0 = nothing)
  logic [3:0] blk_r, blk_g, blk_b;
  logic [11:0] unit_owner_color;
  always_comb begin
    {blk_r, blk_g, blk_b} = 12'h000;
    // city
    if ((city_p1_here || city_p2_here) && city_sprite_pixel != '0)
      {blk_r, blk_g, blk_b} = sprite_color(city_sprite_pixel, player_color(city_p2_here));
    // unit
    unit_owner_color = player_color(unit_table[unit_index].player_owner);
    if (unit_table[unit_index].player_owner == current_player && unit_table[unit_index].moves_left == '0)
      unit_owner_color = dim(unit_owner_color);  // no moves left
    if (unit_selected && selected_unit == unit_index) unit_owner_color = WHITE;  // selected: white
    if (unit_on_tile[UNIT_INDEX_BITS] && unit_sprite_pixel != '0)
      {blk_r, blk_g, blk_b} = sprite_color(unit_sprite_pixel, unit_owner_color);
    // HP bar: one segment per full HP; green if hp > k, else red
    if (unit_on_tile[UNIT_INDEX_BITS] && on_hp_bar && hp_segment < max_hp(unit_table[unit_index].unit_type))
      {blk_r, blk_g, blk_b} = (hp_segment < unit_table[unit_index].hp) ? HP_LEFT : HP_LOST;
    // cursor
    if (cursor_here && on_cursor_frame) {blk_r, blk_g, blk_b} = player_color(current_player);
  end

  // Outside the map: black. Inside: foreground wins where it is non-zero.
  always_comb begin
    if (!on_map) {r, g, b} = 12'h000;
    else if ({blk_r, blk_g, blk_b} != 12'h000) {r, g, b} = {blk_r, blk_g, blk_b};
    else {r, g, b} = {bg_r, bg_g, bg_b};
  end

endmodule
