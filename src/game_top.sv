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
  output logic [15:0] LED,
  output logic        CA, CB, CC, CD, CE, CF, CG,   // seven segment segments
  output logic        DP,                           // decimal point (unused)
  output logic [7:0]  AN                            // seven segment digit selects
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

  // Seven segment display: HP of the unit under the cursor on the two right
  // digits, the player whose turn it is on the leftmost one.
  logic [UNIT_INDEX_BITS:0] unit_at_cursor;             // {found, index}
  logic [HP_BITS-1:0]       cursor_hp;
  logic [3:0]               hp_tens, hp_ones, turn_digit;
  logic [7:0]               digit_en;
  assign unit_at_cursor = find_unit(unit_table, cursor_x, cursor_y);
  assign cursor_hp      = unit_table[unit_at_cursor[UNIT_INDEX_BITS-1:0]].hp;

  always_comb begin
    // HP is 0..10, so the tens digit is 1 or 0
    hp_tens    = (cursor_hp >= 4'd10) ? 4'd1 : 4'd0;
    hp_ones    = (cursor_hp >= 4'd10) ? cursor_hp - 4'd10 : cursor_hp;
    turn_digit = current_player ? 4'd2 : 4'd1;
    // leftmost digit always, the two HP digits only with a unit under the cursor
    digit_en   = unit_at_cursor[UNIT_INDEX_BITS] ? 8'b1000_0011 : 8'b1000_0000;
  end

  // One digit step every 2^17 clocks: 637 Hz, so all eight are redrawn at 80 Hz
  logic seg_tick;
  assign seg_tick = (heartbeat[16:0] == '0);

  multidigit u_multidigit (
    .clk (pixclk),
    .rst (rst),
    .tick(seg_tick),
    .dig0(hp_ones),
    .dig1(hp_tens),
    .dig2(4'd0),
    .dig3(4'd0),
    .dig4(4'd0),
    .dig5(4'd0),
    .dig6(4'd0),
    .dig7(turn_digit),
    .en  (digit_en),
    .a   (CA),
    .b   (CB),
    .c   (CC),
    .d   (CD),
    .e   (CE),
    .f   (CF),
    .g   (CG),
    .an  (AN)
  );

  assign DP = 1'b1;   // active low, so the point stays off

  // LEDs: 0 clock locked, 1 heartbeat, 14/15 whose turn
  always_comb begin
    LED     = '0;
    LED[0]  = locked;
    LED[1]  = heartbeat[25];
    LED[14] = (current_player == 1'b0);
    LED[15] = (current_player == 1'b1);
  end

endmodule
