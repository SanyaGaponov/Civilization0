// game_top.sv - top level (slide 11). Wiring only, no logic.
// Port names match the Digilent Nexys A7 master XDC.
module game_top
  import game_pkg::*;
#(
  parameter string MAP_FILE = "map0.mem"
)(
  input  logic       CLK100MHZ,
  input  logic       CPU_RESETN,   // red reset button, active low
  output logic [3:0] VGA_R,
  output logic [3:0] VGA_G,
  output logic [3:0] VGA_B,
  output logic       VGA_HS,
  output logic       VGA_VS,
  output logic [1:0] LED           // LED0 = clock locked, LED1 = heartbeat blink
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
  logic              hsync, vsync, de;
  /* verilator lint_off UNUSEDSIGNAL */
  logic              frame_end;   // unused for now; will drive the 60 Hz game tick
  /* verilator lint_on UNUSEDSIGNAL */
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

  // ---- terrain map ----
  logic [MAP_ADDR_W-1:0] map_addr;
  logic [TERRAIN_W-1:0]  map_data;
  terrain_rom #(.INIT_FILE(MAP_FILE)) u_terrain (
    .clk   (clk_pix),
    .addr_b(map_addr),
    .data_b(map_data)
  );

  // ---- renderer ----
  drawcon #(.GRID(1'b0)) u_drawcon (
    .clk     (clk_pix),
    .hsync_in(hsync),
    .vsync_in(vsync),
    .de_in   (de),
    .x       (x),
    .y       (y),
    .map_addr(map_addr),
    .map_data(map_data),
    .vga_r   (VGA_R),
    .vga_g   (VGA_G),
    .vga_b   (VGA_B),
    .vga_hs  (VGA_HS),
    .vga_vs  (VGA_VS)
  );

  // ---- debug LEDs: prove the bitstream is alive even if the monitor is dark ----
  logic [25:0] heartbeat;
  always_ff @(posedge clk_pix) heartbeat <= heartbeat + 1'b1;
  assign LED[0] = locked;
  assign LED[1] = heartbeat[25];   // ~1.6 Hz blink at 106 MHz, ~0.4 Hz at 25 MHz

endmodule
