// Top level: board pins, clock, reset and module wiring.
module game_top
  import game_pkg::*;
#(
  parameter string MAP_FILE    = "map0.mem",
  parameter string SPRITE_FILE = "sprites.mem"
)(
  input  logic        clk,          // 100 MHz
  input  logic        CPU_RESETN,
  input  logic        BTNC,
  input  logic        BTNU,
  input  logic        BTND,
  input  logic        BTNL,
  input  logic        BTNR,
  output logic [3:0]  pix_r,
  output logic [3:0]  pix_g,
  output logic [3:0]  pix_b,
  output logic        hsync,
  output logic        vsync,
  output logic [15:0] LED
);

  // Pixel clock: 100 MHz -> 83.46 MHz
  logic pixclk, locked;
  clk_wiz_0 u_clk (
    .clk_out1(pixclk),
    .locked  (locked),
    .clk_in1 (clk)
  );

  // Reset: on while the button is pressed or the clock is unstable;
  // released in step with pixclk.
  logic       reset_request_n, rst;
  logic [1:0] reset_sync;
  assign reset_request_n = CPU_RESETN & locked;
  always_ff @(posedge pixclk or negedge reset_request_n) begin
    if (!reset_request_n) reset_sync <= 2'b11;
    else                  reset_sync <= {reset_sync[0], 1'b0};
  end
  assign rst = reset_sync[1];

  // VGA output
  logic [3:0]        r, g, b;
  logic [10:0]       curr_x;
  logic [9:0]        curr_y;
  vga_out u_vga_out (
    .clk   (pixclk),
    .rst   (rst),
    .r     (r),
    .g     (g),
    .b     (b),
    .pix_r (pix_r),
    .pix_g (pix_g),
    .pix_b (pix_b),
    .hsync (hsync),
    .vsync (vsync),
    .curr_x(curr_x),
    .curr_y(curr_y)
  );

  // Buttons: one 1-clock pulse per press
  logic [NUM_BUTTONS-1:0] press;
  button u_btn_c (.clk(pixclk), .rst(rst), .pressed_signal(BTNC), .pressed_finally(press[BTN_CENTER]));
  button u_btn_u (.clk(pixclk), .rst(rst), .pressed_signal(BTNU), .pressed_finally(press[BTN_UP]));
  button u_btn_d (.clk(pixclk), .rst(rst), .pressed_signal(BTND), .pressed_finally(press[BTN_DOWN]));
  button u_btn_l (.clk(pixclk), .rst(rst), .pressed_signal(BTNL), .pressed_finally(press[BTN_LEFT]));
  button u_btn_r (.clk(pixclk), .rst(rst), .pressed_signal(BTNR), .pressed_finally(press[BTN_RIGHT]));

  // Terrain map: one read for game_ctrl, one for drawcon
  logic [MAP_ADDR_BITS-1:0] target_terrain_addr, tile_terrain_addr;
  logic [TERRAIN_BITS-1:0]  target_terrain, tile_terrain;
  terrain_memory #(.MAP_FILE(MAP_FILE)) u_terrain (
    .game_addr(target_terrain_addr),
    .game_data(target_terrain),
    .draw_addr(tile_terrain_addr),
    .draw_data(tile_terrain)
  );

  // Sprites: one read for units, one for cities
  logic [SPRITE_ADDR_BITS-1:0] unit_sprite_addr, city_sprite_addr;
  logic [PIXEL_BITS-1:0]       unit_sprite_pixel, city_sprite_pixel;
  sprite_memory #(.SPRITE_FILE(SPRITE_FILE)) u_sprites (
    .unit_addr (unit_sprite_addr),
    .unit_pixel(unit_sprite_pixel),
    .city_addr (city_sprite_addr),
    .city_pixel(city_sprite_pixel)
  );

  // Game rules and state
  tile_x_t                    cursor_x;
  tile_y_t                    cursor_y;
  player_t                    current_player;
  logic                       unit_selected;
  logic [UNIT_INDEX_BITS-1:0] selected_unit;
  unit_t [MAX_UNITS-1:0]      unit_table;
  game_ctrl u_game (
    .clk                (pixclk),
    .rst                (rst),
    .press              (press),
    .target_terrain_addr(target_terrain_addr),
    .target_terrain     (target_terrain),
    .cursor_x           (cursor_x),
    .cursor_y           (cursor_y),
    .current_player     (current_player),
    .unit_selected      (unit_selected),
    .selected_unit      (selected_unit),
    .unit_table         (unit_table)
  );

  // Free-running counter: LED blink and unit blink
  logic [25:0] heartbeat;
  always_ff @(posedge pixclk) heartbeat <= heartbeat + 1'b1;

  // Pixel colours
  drawcon u_drawcon (
    .draw_x           (curr_x),
    .draw_y           (curr_y),
    .tile_terrain_addr(tile_terrain_addr),
    .tile_terrain     (tile_terrain),
    .unit_sprite_addr (unit_sprite_addr),
    .unit_sprite_pixel(unit_sprite_pixel),
    .city_sprite_addr (city_sprite_addr),
    .city_sprite_pixel(city_sprite_pixel),
    .cursor_x         (cursor_x),
    .cursor_y         (cursor_y),
    .current_player   (current_player),
    .unit_selected    (unit_selected),
    .selected_unit    (selected_unit),
    .unit_table       (unit_table),
    .blink            (heartbeat[24]),   // ~0.2 s
    .r                (r),
    .g                (g),
    .b                (b)
  );

  // LEDs: 0 clock locked, 1 heartbeat, 14/15 whose turn
  always_comb begin
    LED     = '0;
    LED[0]  = locked;
    LED[1]  = heartbeat[25];
    LED[14] = (current_player == 1'b0);
    LED[15] = (current_player == 1'b1);
  end

endmodule
