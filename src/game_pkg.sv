// Shared constants and types.
/* verilator lint_off UNUSEDPARAM */
package game_pkg;

  // Map geometry
  localparam int TILE_BITS     = 5;                       // tiles are 32x32 pixels
  localparam int MAP_X_BITS    = 6;                       // stored map: 64 tiles wide
  localparam int MAP_Y_BITS    = 5;                       //             32 tiles high
  localparam int MAP_WIDTH     = 1 << MAP_X_BITS;
  localparam int MAP_HEIGHT    = 1 << MAP_Y_BITS;
  localparam int MAP_ADDR_BITS = MAP_X_BITS + MAP_Y_BITS;  // address = {tile_y, tile_x}

  // Terrain types, 4 bits per tile. Codes must match the map generator.
  localparam int TERRAIN_BITS = 4;
  typedef enum logic [TERRAIN_BITS-1:0] {
    T_OCEAN    = 4'h0,
    T_GRASS    = 4'h1,
    T_PLAINS   = 4'h2,
    T_FOREST   = 4'h3,
    T_HILLS    = 4'h4,
    T_MOUNTAIN = 4'h5
  } terrain_e;

  function automatic logic [11:0] terrain_color(input logic [TERRAIN_BITS-1:0] t);
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

  // non-accesible locations check
  function automatic logic is_walkable(input logic [TERRAIN_BITS-1:0] t);
    return (t != T_OCEAN) && (t != T_MOUNTAIN);
  endfunction

  // Tile coordinates. The playable area is 40x25 tiles = the whole screen.
  typedef logic [MAP_X_BITS-1:0] tile_x_t;
  typedef logic [MAP_Y_BITS-1:0] tile_y_t;
  localparam int SCREEN_TILES_X = 40;
  localparam int SCREEN_TILES_Y = 25;

  // two humans taking turns. 0 = Player 1 (red), 1 = Player 2 (blue)
  typedef logic player_t;

  // colors for players
  function automatic logic [11:0] player_color(input player_t p);
    return p ? 12'h26F : 12'hE22;
  endfunction

  // Hardcoded city per player (tile coordinates).
  localparam tile_x_t CITY_P1_X = 6'd4;
  localparam tile_y_t CITY_P1_Y = 5'd15;
  localparam tile_x_t CITY_P2_X = 6'd34;
  localparam tile_y_t CITY_P2_Y = 5'd13;

  function automatic tile_x_t city_x(input player_t p);
    return p ? CITY_P2_X : CITY_P1_X;
  endfunction
  function automatic tile_y_t city_y(input player_t p);
    return p ? CITY_P2_Y : CITY_P1_Y;
  endfunction

  // Units. A small table in registers; slot i is either empty (in_use = 0)
  // or one unit. Cities will fill empty slots when production is added.
  localparam int MAX_UNITS       = 8;
  localparam int UNIT_INDEX_BITS = 3;
  localparam int MOVES_BITS      = 2;
  localparam int HP_BITS         = 4;
  localparam logic [HP_BITS-1:0] MAX_HP = 4'd10;   // every unit starts with 10 hit points

  typedef enum logic [1:0] {
    U_SPEARMAN = 2'd0,
    U_ARCHER   = 2'd1,
    U_CAVALRY  = 2'd2
  } unit_type_e;

  typedef struct packed {
    logic                  in_use;       // slot holds a unit
    player_t               owner;
    unit_type_e            kind;         // spearman / archer / cavalry
    tile_x_t               x;
    tile_y_t               y;
    logic [MOVES_BITS-1:0] moves_left;   // movement points left this turn
    logic [HP_BITS-1:0]    hp;           // hit points left, 0..MAX_HP
  } unit_t;

  // Fighting: the defender always loses ATTACK_DAMAGE hit points; the attacker
  // loses counter_damage() from the defender's counter-attack.
  localparam logic [HP_BITS-1:0] ATTACK_DAMAGE = 4'd3;
  function automatic logic [HP_BITS-1:0] counter_damage(input unit_type_e attacker);
    return (attacker == U_ARCHER) ? 4'd0 : 4'd1;   // archers shoot from a distance
  endfunction

  // Movement points per turn.
  function automatic logic [MOVES_BITS-1:0] moves_per_turn(input unit_type_e t);
    return (t == U_CAVALRY) ? 2'd2 : 2'd1;
  endfunction

  // Units present at reset: one spearman per player, next to its city.
  function automatic unit_t initial_unit(input int i);
    unit_t u;
    u = '0;
    if (i == 0) u = '{in_use: 1'b1, owner: 1'b0, kind: U_SPEARMAN,
                      x: CITY_P1_X + 6'd1, y: CITY_P1_Y,
                      moves_left: moves_per_turn(U_SPEARMAN), hp: MAX_HP};
    if (i == 1) u = '{in_use: 1'b1, owner: 1'b1, kind: U_SPEARMAN,
                      x: CITY_P2_X - 6'd1, y: CITY_P2_Y,
                      moves_left: moves_per_turn(U_SPEARMAN), hp: MAX_HP};
    return u;
  endfunction

  // Which unit stands on tile (qx, qy)? Returns {found, index}; lowest index wins.
  function automatic logic [UNIT_INDEX_BITS:0] find_unit(input unit_t [MAX_UNITS-1:0] u,
                                                         input tile_x_t qx, input tile_y_t qy);
    logic [UNIT_INDEX_BITS:0] r;
    r = '0;
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (u[i].in_use && u[i].x == qx && u[i].y == qy) r = {1'b1, UNIT_INDEX_BITS'(i)};
    return r;
  endfunction

  // Push buttons (index into the press[] vector)
  localparam int NUM_BUTTONS = 5;
  localparam int BTN_CENTER  = 0;
  localparam int BTN_UP      = 1;
  localparam int BTN_DOWN    = 2;
  localparam int BTN_LEFT    = 3;
  localparam int BTN_RIGHT   = 4;

endpackage
/* verilator lint_on UNUSEDPARAM */
