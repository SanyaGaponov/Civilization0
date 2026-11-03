// Shared constants and types.
/* verilator lint_off UNUSEDPARAM */
package game_pkg;

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
  // Terrain types, 4 bits per tile. Codes must match the map generator.
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

  function automatic logic [11:0] terrain_color(input logic [TERRAIN_W-1:0] t);
    case (t)
      T_OCEAN:    return 12'h15A;   // blue
      T_GRASS:    return 12'h4A3;   // green
      T_PLAINS:   return 12'hBB5;   // yellow-green
      T_FOREST:   return 12'h262;   // dark green
      T_HILLS:    return 12'h864;   // brown
      T_MOUNTAIN: return 12'hAAA;   // grey
      default:    return 12'hF0F;   // magenta = bad map data (debug aid)
    endcase
  endfunction

  // Units can't enter ocean or mountains.
  function automatic logic passable(input logic [TERRAIN_W-1:0] t);
    return (t != T_OCEAN) && (t != T_MOUNTAIN);
  endfunction

  // ---------------------------------------------------------------------------
  // Tile coordinates. The playable area is 40x25 tiles = the whole screen.
  // ---------------------------------------------------------------------------
  typedef logic [MAP_W_LOG2-1:0] tile_x_t;
  typedef logic [MAP_H_LOG2-1:0] tile_y_t;
  localparam int PLAY_W = 40;
  localparam int PLAY_H = 25;

  // ---------------------------------------------------------------------------
  // Players: two humans taking turns. 0 = Player 1 (red), 1 = Player 2 (blue).
  // ---------------------------------------------------------------------------
  typedef logic player_t;

  function automatic logic [11:0] player_color(input player_t p);
    return p ? 12'h26F : 12'hE22;
  endfunction

  // One hardcoded city per player (tile coordinates).
  localparam tile_x_t CITY0_X = 6'd4;   // Player 1, west
  localparam tile_y_t CITY0_Y = 5'd15;
  localparam tile_x_t CITY1_X = 6'd34;  // Player 2, east
  localparam tile_y_t CITY1_Y = 5'd13;

  function automatic tile_x_t city_x(input player_t p);
    return p ? CITY1_X : CITY0_X;
  endfunction
  function automatic tile_y_t city_y(input player_t p);
    return p ? CITY1_Y : CITY0_Y;
  endfunction

  // ---------------------------------------------------------------------------
  // Units. A small table in registers; slot i is either empty (valid = 0)
  // or one unit. Cities will fill empty slots when production is added.
  // ---------------------------------------------------------------------------
  localparam int MAX_UNITS  = 8;
  localparam int UNIT_IDX_W = 3;
  localparam int MOVES_W    = 2;

  typedef enum logic [1:0] {
    U_SPEARMAN = 2'd0,
    U_ARCHER   = 2'd1,
    U_CAVALRY  = 2'd2
  } unit_type_e;

  typedef struct packed {
    logic               valid;   // slot in use
    player_t            owner;
    unit_type_e         utype;
    tile_x_t            x;
    tile_y_t            y;
    logic [MOVES_W-1:0] moves;   // movement points left this turn
  } unit_t;

  // Movement points per turn.
  function automatic logic [MOVES_W-1:0] unit_moves(input unit_type_e t);
    return (t == U_CAVALRY) ? 2'd2 : 2'd1;
  endfunction

  // Units present at reset: one spearman per player, next to its city.
  function automatic unit_t start_unit(input int i);
    unit_t u;
    u = '0;
    if (i == 0) u = '{valid: 1'b1, owner: 1'b0, utype: U_SPEARMAN,
                      x: CITY0_X + 6'd1, y: CITY0_Y, moves: unit_moves(U_SPEARMAN)};
    if (i == 1) u = '{valid: 1'b1, owner: 1'b1, utype: U_SPEARMAN,
                      x: CITY1_X - 6'd1, y: CITY1_Y, moves: unit_moves(U_SPEARMAN)};
    return u;
  endfunction

  // Which unit stands on tile (qx, qy)? Returns {found, index}; lowest index wins.
  function automatic logic [UNIT_IDX_W:0] find_unit(input unit_t [MAX_UNITS-1:0] u,
                                                    input tile_x_t qx, input tile_y_t qy);
    logic [UNIT_IDX_W:0] r;
    r = '0;
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (u[i].valid && u[i].x == qx && u[i].y == qy) r = {1'b1, UNIT_IDX_W'(i)};
    return r;
  endfunction

  // ---------------------------------------------------------------------------
  // Push buttons (index into the press[] vector)
  // ---------------------------------------------------------------------------
  localparam int NUM_BTN = 5;
  localparam int BTN_C = 0;   // centre: select / deselect / end turn
  localparam int BTN_U = 1;
  localparam int BTN_D = 2;
  localparam int BTN_L = 3;
  localparam int BTN_R = 4;

endpackage
/* verilator lint_on UNUSEDPARAM */
