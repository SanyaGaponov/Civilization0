// game_pkg.sv - constants shared by every module.
// Compile this file FIRST (Vivado and Verilator both need packages before users).
`default_nettype none

// Not every module uses every constant; that's expected for a package.
/* verilator lint_off UNUSEDPARAM */
package game_pkg;

  // ---------------------------------------------------------------------------
  // Video mode. Change this ONE line to switch resolution.
  //   MODE_1280x800 : course timing (slide 7), ~106 MHz pixel clock
  //   MODE_640x480  : industry-standard 640x480 @ 60 Hz, works on any VGA monitor
  // ---------------------------------------------------------------------------
  typedef enum int { MODE_1280x800, MODE_640x480 } video_mode_e;
  localparam video_mode_e VIDEO_MODE = MODE_1280x800;

  localparam bit HI_RES = (VIDEO_MODE == MODE_1280x800);

  // Horizontal timing in pixels. Order inside one line (as on slide 7):
  //   [sync pulse][back porch][ACTIVE (visible)][front porch]
  localparam int H_SYNC   = HI_RES ?  136 :  96;
  localparam int H_BP     = HI_RES ?  200 :  48;
  localparam int H_ACTIVE = HI_RES ? 1280 : 640;
  localparam int H_FP     = HI_RES ?   64 :  16;
  localparam int H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;   // 1680 / 800

  // Vertical timing in lines, same order.
  localparam int V_SYNC   = HI_RES ?   3 :   2;
  localparam int V_BP     = HI_RES ?  24 :  33;
  localparam int V_ACTIVE = HI_RES ? 800 : 480;
  localparam int V_FP     = HI_RES ?   1 :  10;
  localparam int V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;   // 828 / 525

  // Sync polarity: value driven DURING the sync pulse.
  // Slide 7 draws the pulses as high; 640x480 is standard negative (low).
  // If a monitor shows "no signal" / "out of range", try flipping these.
  localparam bit H_POL = HI_RES ? 1'b1 : 1'b0;
  localparam bit V_POL = HI_RES ? 1'b1 : 1'b0;

  // Counter widths (enough bits for H_TOTAL-1 and V_TOTAL-1).
  localparam int HCNT_W = 11;   // up to 2047
  localparam int VCNT_W = 10;   // up to 1023

  // Pixel clock from the on-chip MMCM: f = 100 MHz * MULT / (DIV * OUT_DIV)
  //   1280x800: 100 * 10.625 / (1 * 10) = 106.25 MHz
  //   640x480 : 100 * 31.5   / (5 * 25) =  25.2  MHz (standard is 25.175)
  localparam real MMCM_MULT    = HI_RES ? 10.625 : 31.5;
  localparam int  MMCM_DIV     = HI_RES ?  1     :  5;
  localparam real MMCM_OUT_DIV = HI_RES ? 10.0   : 25.0;

  // ---------------------------------------------------------------------------
  // Map geometry
  // ---------------------------------------------------------------------------
  localparam int TILE_LOG2  = 5;                  // tiles are 32x32 pixels
  localparam int TILE_SIZE  = 1 << TILE_LOG2;
  localparam int MAP_W_LOG2 = 6;                  // stored map: 64 tiles wide
  localparam int MAP_H_LOG2 = 5;                  //             32 tiles high
  localparam int MAP_W      = 1 << MAP_W_LOG2;
  localparam int MAP_H      = 1 << MAP_H_LOG2;
  localparam int MAP_ADDR_W = MAP_W_LOG2 + MAP_H_LOG2;  // address = {tile_y, tile_x}

  // ---------------------------------------------------------------------------
  // Terrain types. 4 bits per tile = one hex digit in mem/map0.mem.
  // Keep in sync with LEGEND in scripts/gen_map.py.
  // ---------------------------------------------------------------------------
  localparam int TERRAIN_W = 4;
  typedef enum logic [TERRAIN_W-1:0] {
    T_OCEAN    = 4'h0,
    T_GRASS    = 4'h1,
    T_PLAINS   = 4'h2,
    T_FOREST   = 4'h3,
    T_HILLS    = 4'h4,
    T_MOUNTAIN = 4'h5
  } terrain_e;

endpackage
/* verilator lint_on UNUSEDPARAM */

`default_nettype wire
