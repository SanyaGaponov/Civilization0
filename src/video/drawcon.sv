// drawcon.sv - decides the colour of each pixel (slide 11 "drawcon").
//
// Pipeline (one row = one clock):
//   stage 0  (inputs from vga_out)  x, y -> map address, and "what is on this
//            tile?": a unit, a city, the cursor (comparisons, no memory)
//   stage 1  terrain ROM returns the tile type   (ROM latency = 1 clock)
//   stage 2  combine the layers into one colour, registered to the pins
//
// Layers, bottom to top:  terrain -> city -> unit -> cursor
//   city   : square in the owner's colour, black border, white centre
//   unit   : triangle in the owner's colour, black outline
//            (all unit types are triangles for now; sprites come later)
//            selected unit blinks white; own unit with no moves left is dimmed
//   cursor : 2-pixel frame around the tile, in the current player's colour
//
// The colour appears 2 clocks after x/y, so hsync, vsync and de are delayed
// by the same 2 clocks (see course README "timing issues").
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
  input  logic                  frame_end,   // 1 pulse per frame, drives blinking
  // to / from the terrain map (port B)
  output logic [MAP_ADDR_W-1:0] map_addr,
  input  logic [TERRAIN_W-1:0]  map_data,
  // game state from game_ctrl
  input  tile_x_t               cursor_x,
  input  tile_y_t               cursor_y,
  input  player_t               cur_player,
  input  logic                  sel_valid,
  input  logic [UNIT_IDX_W-1:0] sel_idx,
  input  unit_t [MAX_UNITS-1:0] units,
  // to the VGA pins (stage 2)
  output logic [3:0]            vga_r,
  output logic [3:0]            vga_g,
  output logic [3:0]            vga_b,
  output logic                  vga_hs,
  output logic                  vga_vs
);

  // ---- stage 0: which tile, and what stands on it --------------------------
  tile_x_t tile_x;
  tile_y_t tile_y;
  assign tile_x   = x[TILE_LOG2 +: MAP_W_LOG2];   // x[10:5]
  assign tile_y   = y[TILE_LOG2 +: MAP_H_LOG2];   // y[9:5]
  assign map_addr = {tile_y, tile_x};

  logic [UNIT_IDX_W:0] unit_here;                 // {found, index}
  assign unit_here = find_unit(units, tile_x, tile_y);

  logic city0_here, city1_here, cursor_here;
  assign city0_here  = (tile_x == CITY0_X) && (tile_y == CITY0_Y);
  assign city1_here  = (tile_x == CITY1_X) && (tile_y == CITY1_Y);
  assign cursor_here = (tile_x == cursor_x) && (tile_y == cursor_y);

  // ---- stage 1: register everything while the ROM reads ---------------------
  logic                 hs1, vs1, de1, edge1;
  logic [TILE_LOG2-1:0] px1, py1;                 // pixel position inside the tile
  logic                 unit1, unit_owner1, unit_dim1, unit_sel1;
  logic                 city1, city_owner1, cursor1;

  always_ff @(posedge clk) begin
    hs1   <= hsync_in;
    vs1   <= vsync_in;
    de1   <= de_in;
    px1   <= x[TILE_LOG2-1:0];
    py1   <= y[TILE_LOG2-1:0];
    edge1 <= (x[TILE_LOG2-1:0] == '0) || (y[TILE_LOG2-1:0] == '0);

    unit1       <= unit_here[UNIT_IDX_W];
    unit_owner1 <= units[unit_here[UNIT_IDX_W-1:0]].owner;
    unit_dim1   <= units[unit_here[UNIT_IDX_W-1:0]].owner == cur_player &&
                   units[unit_here[UNIT_IDX_W-1:0]].moves == '0;
    unit_sel1   <= sel_valid && (sel_idx == unit_here[UNIT_IDX_W-1:0]);

    city1       <= city0_here || city1_here;
    city_owner1 <= city1_here;                    // city 1 belongs to Player 2
    cursor1     <= cursor_here;
  end

  // ---- blink: toggles every 32 frames ---------------------------------------
  logic [5:0] frame_cnt;
  always_ff @(posedge clk) if (frame_end) frame_cnt <= frame_cnt + 1'b1;
  logic blink;
  assign blink = frame_cnt[5];

  // ---- stage 2: shapes (comparisons on the pixel position inside the tile) --
  // Triangle: apex at the top centre (row 5), base at row 26, 20 px wide.
  logic [TILE_LOG2-1:0] dx, hw;
  logic tri_in, tri_edge;
  always_comb begin
    dx       = px1[4] ? px1 - 5'd16 : 5'd15 - px1;   // distance from the centre line
    hw       = (py1 - 5'd5) >> 1;                     // half-width grows downwards
    tri_in   = (py1 >= 5'd5) && (py1 <= 5'd26) && (dx <= hw);
    tri_edge = tri_in && ((py1 >= 5'd25) || (dx >= hw) || (dx + 5'd1 == hw));
  end

  // City: square from 5 to 26, 2-px black border, white 6x6 centre.
  logic city_in, city_border, city_centre;
  assign city_in     = (px1 >= 5'd5)  && (px1 <= 5'd26) && (py1 >= 5'd5)  && (py1 <= 5'd26);
  assign city_border = city_in && (px1 <= 5'd6 || px1 >= 5'd25 || py1 <= 5'd6 || py1 >= 5'd25);
  assign city_centre = (px1 >= 5'd13) && (px1 <= 5'd18) && (py1 >= 5'd13) && (py1 <= 5'd18);

  // Cursor: 2-px frame at the tile edges.
  logic cursor_frame;
  assign cursor_frame = (px1 <= 5'd1) || (px1 >= 5'd30) || (py1 <= 5'd1) || (py1 >= 5'd30);

  function automatic logic [11:0] half(input logic [11:0] c);
    return (c >> 1) & 12'h777;   // halve each 4-bit channel
  endfunction

  logic [11:0] rgb, unit_fill;
  always_comb begin
    // terrain
    rgb = terrain_color(map_data);
    if (GRID && edge1) rgb = half(rgb);
    // city
    if (city1 && city_in)
      rgb = city_border ? 12'h000 : (city_centre ? 12'hFFF : player_color(city_owner1));
    // unit
    unit_fill = player_color(unit_owner1);
    if (unit_dim1)          unit_fill = half(unit_fill);
    if (unit_sel1 && blink) unit_fill = 12'hFFF;
    if (unit1 && tri_in)
      rgb = tri_edge ? 12'h000 : unit_fill;
    // cursor
    if (cursor1 && cursor_frame)
      rgb = player_color(cur_player);
  end

  always_ff @(posedge clk) begin
    vga_hs <= hs1;
    vga_vs <= vs1;
    // Outside the visible area the colour MUST be black, or the monitor
    // mis-detects the black level.
    {vga_r, vga_g, vga_b} <= de1 ? rgb : 12'h000;
  end

endmodule
