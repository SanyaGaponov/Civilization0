// Shared constants, types and helper functions.
/* verilator lint_off UNUSEDPARAM */
package game_pkg;

  // Map geometry
  localparam int TILE_BITS     = 5;                       // tile = 32x32 pixels
  localparam int MAP_X_BITS    = 5;                       // stored map: 32 tiles wide
  localparam int MAP_Y_BITS    = 5;                       //             32 tiles high
  localparam int MAP_WIDTH     = 1 << MAP_X_BITS;
  localparam int MAP_HEIGHT    = 1 << MAP_Y_BITS;
  localparam int MAP_ADDR_BITS = MAP_X_BITS + MAP_Y_BITS;  // address = {tile_y, tile_x}

  // Terrain codes (must match scripts/gen_map.py)
  localparam int TERRAIN_BITS = 4;
  typedef enum logic [TERRAIN_BITS-1:0] {
    T_OCEAN    = 4'h0,
    T_GRASS    = 4'h1,
    T_PLAINS   = 4'h2,
    T_FOREST   = 4'h3,
    T_HILLS    = 4'h4,
    T_MOUNTAIN = 4'h5
  } terrain_e;

  // Terrain colour, 12-bit RGB
  function automatic logic [11:0] terrain_color(input logic [TERRAIN_BITS-1:0] t);
    case (t)
      T_OCEAN:    return 12'h15A;   // blue
      T_GRASS:    return 12'h4A3;   // green
      T_PLAINS:   return 12'hBB5;   // yellow-green
      T_FOREST:   return 12'h262;   // dark green
      T_HILLS:    return 12'h864;   // brown
      T_MOUNTAIN: return 12'hAAA;   // grey
      default:    return 12'hF0F;   // magenta: bad map data
    endcase
  endfunction

  // Units can't enter ocean or mountains
  function automatic logic is_walkable(input logic [TERRAIN_BITS-1:0] t);
    return (t != T_OCEAN) && (t != T_MOUNTAIN);
  endfunction

  // Tile coordinates; the playable map is 32x20 tiles
  typedef logic [MAP_X_BITS-1:0] tile_x_t;
  typedef logic [MAP_Y_BITS-1:0] tile_y_t;
  localparam int PLAY_TILES_X = 32;
  localparam int PLAY_TILES_Y = 20;

  // Map position on the 1280x800 screen (pixels): centred
  localparam int MAP_LEFT = (1280 - (PLAY_TILES_X << TILE_BITS)) / 2;   // 128
  localparam int MAP_TOP  = (800  - (PLAY_TILES_Y << TILE_BITS)) / 2;   // 80

  // Players: 0 = Player 1 (red), 1 = Player 2 (blue)
  typedef logic player_t;

  function automatic logic [11:0] player_color(input player_t p);
    return p ? 12'h26F : 12'hE22;
  endfunction

  // One fixed city per player (tile coordinates)
  localparam tile_x_t CITY_P1_X = 5'd4;
  localparam tile_y_t CITY_P1_Y = 5'd10;
  localparam tile_x_t CITY_P2_X = 5'd27;
  localparam tile_y_t CITY_P2_Y = 5'd9;

  function automatic tile_x_t city_x(input player_t p);
    return p ? CITY_P2_X : CITY_P1_X;
  endfunction
  function automatic tile_y_t city_y(input player_t p);
    return p ? CITY_P2_Y : CITY_P1_Y;
  endfunction

  // Units: a table of MAX_UNITS slots; a slot is empty when in_use = 0
  localparam int MAX_UNITS       = 8;
  localparam int UNIT_INDEX_BITS = 3;
  localparam int MOVES_BITS      = 2;
  localparam int HP_BITS         = 4;
  localparam logic [HP_BITS-1:0] MAX_HP = 4'd10;   // largest HP = HP bar length

  typedef enum logic [1:0] {
    U_SPEARMAN = 2'd0,
    U_ARCHER   = 2'd1,
    U_CAVALRY  = 2'd2
  } unit_type_e;

  typedef struct packed {
    logic                  in_use;       // slot holds a unit
    player_t               owner;
    unit_type_e            kind;
    tile_x_t               x;
    tile_y_t               y;
    logic [MOVES_BITS-1:0] moves_left;   // movement points left this turn
    logic [HP_BITS-1:0]    hp;           // hit points left
  } unit_t;

  // Fighting: defender loses ATTACK_DAMAGE, attacker loses counter_damage()
  localparam logic [HP_BITS-1:0] ATTACK_DAMAGE = 4'd3;
  function automatic logic [HP_BITS-1:0] counter_damage(input unit_type_e attacker);
    return (attacker == U_ARCHER) ? 4'd0 : 4'd1;   // archers attack from range
  endfunction

  // Full HP per unit type
  function automatic logic [HP_BITS-1:0] max_hp(input unit_type_e t);
    return (t == U_ARCHER) ? 4'd6 : MAX_HP;
  endfunction

  // Movement points per turn
  function automatic logic [MOVES_BITS-1:0] moves_per_turn(input unit_type_e t);
    return (t == U_CAVALRY) ? 2'd2 : 2'd1;
  endfunction

  // New unit with full HP and moves
  function automatic unit_t new_unit(input player_t owner, input unit_type_e kind,
                                     input tile_x_t x, input tile_y_t y);
    return '{in_use: 1'b1, owner: owner, kind: kind, x: x, y: y,
             moves_left: moves_per_turn(kind), hp: max_hp(kind)};
  endfunction

  // Units at reset. Slots 0-2: Player 1, 3-5: Player 2, 6-7: empty.
  function automatic unit_t initial_unit(input int i);
    case (i)
      0: return new_unit(1'b0, U_SPEARMAN, CITY_P1_X + 5'd1, CITY_P1_Y);          // east of city
      1: return new_unit(1'b0, U_ARCHER,   CITY_P1_X,        CITY_P1_Y - 5'd1);   // north
      2: return new_unit(1'b0, U_CAVALRY,  CITY_P1_X,        CITY_P1_Y + 5'd1);   // south
      3: return new_unit(1'b1, U_SPEARMAN, CITY_P2_X - 5'd1, CITY_P2_Y);          // west of city
      4: return new_unit(1'b1, U_ARCHER,   CITY_P2_X + 5'd1, CITY_P2_Y);          // east
      5: return new_unit(1'b1, U_CAVALRY,  CITY_P2_X,        CITY_P2_Y + 5'd1);   // south
      default: return '0;
    endcase
  endfunction

  // Unit on tile (qx, qy): returns {found, index}; lowest index wins
  function automatic logic [UNIT_INDEX_BITS:0] find_unit(input unit_t [MAX_UNITS-1:0] u,
                                                         input tile_x_t qx, input tile_y_t qy);
    logic [UNIT_INDEX_BITS:0] r;
    r = '0;
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (u[i].in_use && u[i].x == qx && u[i].y == qy) r = {1'b1, UNIT_INDEX_BITS'(i)};
    return r;
  endfunction

  // Button positions in the press[] vector
  localparam int NUM_BUTTONS = 5;
  localparam int BTN_CENTER  = 0;
  localparam int BTN_UP      = 1;
  localparam int BTN_DOWN    = 2;
  localparam int BTN_LEFT    = 3;
  localparam int BTN_RIGHT   = 4;

endpackage
/* verilator lint_on UNUSEDPARAM */
