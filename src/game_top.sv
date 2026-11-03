// game_top.sv - top level (slide 11). Wiring only, no logic.
// Port names match the Digilent Nexys A7 master XDC.
module game_top
  import game_pkg::*;
#(
  parameter string MAP_FILE    = "map0.mem",
  parameter int    DEBOUNCE_W  = 20           // button debounce = 2^20 clocks (~10 ms)
)(
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,   // red reset button, active low
  input  logic        BTNC,         // centre: select / deselect / end turn
  input  logic        BTNU,
  input  logic        BTND,
  input  logic        BTNL,
  input  logic        BTNR,
  output logic [3:0]  VGA_R,
  output logic [3:0]  VGA_G,
  output logic [3:0]  VGA_B,
  output logic        VGA_HS,
  output logic        VGA_VS,
  output logic [15:0] LED           // 0: clock locked, 1: heartbeat, 14/15: whose turn
);

  // ---- clock + reset ----
  logic clk_pix, rst_pix, locked;
  clk_gen u_clk_gen (
    .clk_100m (CLK100MHZ),
    .rst_btn_n(CPU_RESETN),
    .clk_pix  (clk_pix),
    .rst_pix  (rst_pix),
    .locked   (locked)
  );

  // ---- VGA timing ----
  logic              hsync, vsync, de, frame_end;
  logic [HCNT_W-1:0] x;
  logic [VCNT_W-1:0] y;
  vga_out u_vga_out (
    .clk      (clk_pix),
    .rst      (rst_pix),
    .hsync    (hsync),
    .vsync    (vsync),
    .de       (de),
    .x        (x),
    .y        (y),
    .frame_end(frame_end)
  );

  // ---- buttons -> 1-clock press pulses ----
  logic [NUM_BTN-1:0] btn_raw, press;
  always_comb begin
    btn_raw        = '0;
    btn_raw[BTN_C] = BTNC;
    btn_raw[BTN_U] = BTNU;
    btn_raw[BTN_D] = BTND;
    btn_raw[BTN_L] = BTNL;
    btn_raw[BTN_R] = BTNR;
  end
  buttons #(.N(NUM_BTN), .CNT_W(DEBOUNCE_W)) u_buttons (
    .clk  (clk_pix),
    .rst  (rst_pix),
    .raw  (btn_raw),
    .press(press)
  );

  // ---- terrain map: port A for game logic, port B for the renderer ----
  logic [MAP_ADDR_W-1:0] terr_addr_a, map_addr;
  logic [TERRAIN_W-1:0]  terr_data_a, map_data;
  terrain_rom #(.INIT_FILE(MAP_FILE)) u_terrain (
    .clk   (clk_pix),
    .addr_a(terr_addr_a),
    .data_a(terr_data_a),
    .addr_b(map_addr),
    .data_b(map_data)
  );

  // ---- game logic ----
  tile_x_t               cursor_x;
  tile_y_t               cursor_y;
  player_t               cur_player;
  logic                  sel_valid;
  logic [UNIT_IDX_W-1:0] sel_idx;
  unit_t [MAX_UNITS-1:0] units;
  game_ctrl u_game (
    .clk       (clk_pix),
    .rst       (rst_pix),
    .press     (press),
    .terr_addr (terr_addr_a),
    .terr_data (terr_data_a),
    .cursor_x  (cursor_x),
    .cursor_y  (cursor_y),
    .cur_player(cur_player),
    .sel_valid (sel_valid),
    .sel_idx   (sel_idx),
    .units     (units)
  );

  // ---- renderer ----
  drawcon #(.GRID(1'b0)) u_drawcon (
    .clk       (clk_pix),
    .hsync_in  (hsync),
    .vsync_in  (vsync),
    .de_in     (de),
    .x         (x),
    .y         (y),
    .frame_end (frame_end),
    .map_addr  (map_addr),
    .map_data  (map_data),
    .cursor_x  (cursor_x),
    .cursor_y  (cursor_y),
    .cur_player(cur_player),
    .sel_valid (sel_valid),
    .sel_idx   (sel_idx),
    .units     (units),
    .vga_r     (VGA_R),
    .vga_g     (VGA_G),
    .vga_b     (VGA_B),
    .vga_hs    (VGA_HS),
    .vga_vs    (VGA_VS)
  );

  // ---- LEDs ----
  logic [25:0] heartbeat;
  always_ff @(posedge clk_pix) heartbeat <= heartbeat + 1'b1;
  always_comb begin
    LED     = '0;
    LED[0]  = locked;              // pixel clock is stable
    LED[1]  = heartbeat[25];       // blinks: the design is running
    LED[14] = (cur_player == 1'b0);  // Player 1 (red) to move
    LED[15] = (cur_player == 1'b1);  // Player 2 (blue) to move
  end

endmodule
