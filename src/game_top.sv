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
  logic       rst_in_n, rst;
  logic [1:0] rst_sync;
  assign rst_in_n = CPU_RESETN & locked;
  always_ff @(posedge pixclk or negedge rst_in_n) begin
    if (!rst_in_n) rst_sync <= 2'b11;
    else           rst_sync <= {rst_sync[0], 1'b0};
  end
  assign rst = rst_sync[1];

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
  logic [NUM_BTN-1:0] press;
  button u_btn_c (.clk(pixclk), .rst(rst), .pressed_signal(BTNC), .pressed_finally(press[BTN_C]));
  button u_btn_u (.clk(pixclk), .rst(rst), .pressed_signal(BTNU), .pressed_finally(press[BTN_U]));
  button u_btn_d (.clk(pixclk), .rst(rst), .pressed_signal(BTND), .pressed_finally(press[BTN_D]));
  button u_btn_l (.clk(pixclk), .rst(rst), .pressed_signal(BTNL), .pressed_finally(press[BTN_L]));
  button u_btn_r (.clk(pixclk), .rst(rst), .pressed_signal(BTNR), .pressed_finally(press[BTN_R]));

  // ---- terrain map: one read for game logic, one for drawcon ----
  logic [MAP_ADDR_W-1:0] terr_addr, map_addr;
  logic [TERRAIN_W-1:0]  terr_data, map_data;
  terrain_memory #(.world_map_file(MAP_FILE)) u_terrain (
    .game_addr(terr_addr),
    .game_data(terr_data),
    .draw_addr(map_addr),
    .draw_data(map_data)
  );

  // ---- game logic ----
  tile_x_t               cursor_x;
  tile_y_t               cursor_y;
  player_t               cur_player;
  logic                  sel_valid;
  logic [UNIT_IDX_W-1:0] sel_idx;
  unit_t [MAX_UNITS-1:0] units;
  game_ctrl u_game (
    .clk       (pixclk),
    .rst       (rst),
    .press     (press),
    .terr_addr (terr_addr),
    .terr_data (terr_data),
    .cursor_x  (cursor_x),
    .cursor_y  (cursor_y),
    .cur_player(cur_player),
    .sel_valid (sel_valid),
    .sel_idx   (sel_idx),
    .units     (units)
  );

  logic [25:0] heartbeat;
  always_ff @(posedge pixclk) heartbeat <= heartbeat + 1'b1;

  drawcon u_drawcon (
    .draw_x    (curr_x),
    .draw_y    (curr_y),
    .map_addr  (map_addr),
    .map_data  (map_data),
    .cursor_x  (cursor_x),
    .cursor_y  (cursor_y),
    .cur_player(cur_player),
    .sel_valid (sel_valid),
    .sel_idx   (sel_idx),
    .units     (units),
    .blink     (heartbeat[24]),   // toggles every ~0.2 s
    .r         (r),
    .g         (g),
    .b         (b)
  );

  always_comb begin
    LED     = '0;
    LED[0]  = locked;
    LED[1]  = heartbeat[25];
    LED[14] = (cur_player == 1'b0);
    LED[15] = (cur_player == 1'b1);
  end

endmodule
