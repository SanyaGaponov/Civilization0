// Top level: board pins, clock, reset and module wiring.
module game_top
  import game_pkg::*;
#(
  parameter string MAP_FILE = "map0.mem"
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

  // 100 MHz -> 83.46 MHz
  logic pixclk, locked;
  clk_wiz_0 u_clk (
    .clk_out1(pixclk),
    .locked  (locked),
    .clk_in1 (clk)
  );

  // ---- reset: held while the button is pressed or the clock is not yet stable.
  // It turns on immediately and turns off on a pixclk edge (after 2 edges),
  // so the button, which is not aligned to the clock, can't cause trouble.
  logic       reset_request_n, rst;
  logic [1:0] reset_sync;
  assign reset_request_n = CPU_RESETN & locked;
  always_ff @(posedge pixclk or negedge reset_request_n) begin
    if (!reset_request_n) reset_sync <= 2'b11;
    else                  reset_sync <= {reset_sync[0], 1'b0};
  end
  assign rst = reset_sync[1];

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

  // ---- buttons -> 1-clock press pulses ----
  logic [NUM_BUTTONS-1:0] press;
  button u_btn_c (.clk(pixclk), .rst(rst), .pressed_signal(BTNC), .pressed_finally(press[BTN_CENTER]));
  button u_btn_u (.clk(pixclk), .rst(rst), .pressed_signal(BTNU), .pressed_finally(press[BTN_UP]));
  button u_btn_d (.clk(pixclk), .rst(rst), .pressed_signal(BTND), .pressed_finally(press[BTN_DOWN]));
  button u_btn_l (.clk(pixclk), .rst(rst), .pressed_signal(BTNL), .pressed_finally(press[BTN_LEFT]));
  button u_btn_r (.clk(pixclk), .rst(rst), .pressed_signal(BTNR), .pressed_finally(press[BTN_RIGHT]));

  // ---- terrain map: one read for game logic, one for drawcon ----
  logic [MAP_ADDR_BITS-1:0] target_terrain_addr, tile_terrain_addr;
  logic [TERRAIN_BITS-1:0]  target_terrain, tile_terrain;
  terrain_memory #(.MAP_FILE(MAP_FILE)) u_terrain (
    .game_addr(target_terrain_addr),
    .game_data(target_terrain),
    .draw_addr(tile_terrain_addr),
    .draw_data(tile_terrain)
  );

  // ---- game logic ----
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

  logic [25:0] heartbeat;
  always_ff @(posedge pixclk) heartbeat <= heartbeat + 1'b1;

  drawcon u_drawcon (
    .draw_x           (curr_x),
    .draw_y           (curr_y),
    .tile_terrain_addr(tile_terrain_addr),
    .tile_terrain     (tile_terrain),
    .cursor_x         (cursor_x),
    .cursor_y         (cursor_y),
    .current_player   (current_player),
    .unit_selected    (unit_selected),
    .selected_unit    (selected_unit),
    .unit_table       (unit_table),
    .blink            (heartbeat[24]),   // toggles every ~0.2 s
    .r                (r),
    .g                (g),
    .b                (b)
  );

  always_comb begin
    LED     = '0;
    LED[0]  = locked;
    LED[1]  = heartbeat[25];
    LED[14] = (current_player == 1'b0);
    LED[15] = (current_player == 1'b1);
  end

endmodule
