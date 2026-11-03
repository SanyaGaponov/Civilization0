// Top level: board pins, clock, reset and module wiring.
module game_top
  import game_pkg::*;
#(
  parameter string MAP_FILE   = "map0.mem",
  parameter int    DEBOUNCE_W = 20            // button debounce = 2^20 clocks (~12 ms)
)(
  input  logic        clk,          // 100 MHz board clock
  input  logic        CPU_RESETN,   // red reset button, active low
  input  logic        BTNC,         // centre: select / deselect / end turn
  input  logic        BTNU,
  input  logic        BTND,
  input  logic        BTNL,
  input  logic        BTNR,
  output logic [3:0]  pix_r,        // VGA connector
  output logic [3:0]  pix_g,
  output logic [3:0]  pix_b,
  output logic        hsync,
  output logic        vsync,
  output logic [15:0] LED           // 0: clock locked, 1: heartbeat, 14/15: whose turn
);

  // ---- pixel clock: 100 MHz -> 83.46 MHz (Clocking Wizard IP) ----
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

  // ---- VGA controller ----
  logic [3:0]        r, g, b;          // colour from drawcon
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
    .clk  (pixclk),
    .rst  (rst),
    .raw  (btn_raw),
    .press(press)
  );

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

  // ---- heartbeat counter: LED1 blink and the selected unit's blinking ----
  logic [25:0] heartbeat;
  always_ff @(posedge pixclk) heartbeat <= heartbeat + 1'b1;

  // ---- drawing logic ----
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

  // ---- LEDs ----
  always_comb begin
    LED     = '0;
    LED[0]  = locked;                // pixel clock is stable
    LED[1]  = heartbeat[25];         // blinks: the design is running
    LED[14] = (cur_player == 1'b0);  // Player 1 (red) to move
    LED[15] = (cur_player == 1'b1);  // Player 2 (blue) to move
  end

endmodule
