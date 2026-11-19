/* verilator lint_off UNUSEDPARAM */
package game_pkg;

  // Map geometry
  localparam int TILE_BITS = 5;  // tile = 32x32 pixels
  localparam int MAP_X_BITS = 5;  // stored map: 32 tiles wide
  localparam int MAP_Y_BITS = 5;  //             32 tiles high
  localparam int MAP_WIDTH = 1 << MAP_X_BITS;
  localparam int MAP_HEIGHT = 1 << MAP_Y_BITS;
  localparam int MAP_ADDR_BITS = MAP_X_BITS + MAP_Y_BITS;  // address = {tile_y, tile_x}


  // -------------------------------------------- TERRAIN --------------------------------------------
  // Terrain codes (inshala match scripts/gen_map.py)
  localparam int TERRAIN_BITS = 3;
  typedef enum logic [TERRAIN_BITS-1:0] {
    T_OCEAN    = 3'h0,
    T_GRASS    = 3'h1,
    T_PLAINS   = 3'h2,
    T_FOREST   = 3'h3,
    T_HILLS    = 3'h4,
    T_MOUNTAIN = 3'h5
  } terrain_e;

  // Terrain colour, 12-bit RGB
  function automatic logic [11:0] terrain_color(input logic [TERRAIN_BITS-1:0] t);
    case (t)
      T_OCEAN:    return 12'h15A;  // blue
      T_GRASS:    return 12'h4A3;  // green
      T_PLAINS:   return 12'hBB5;  // yellow green
      T_FOREST:   return 12'h262;  // dark green
      T_HILLS:    return 12'h864;  // brown
      T_MOUNTAIN: return 12'hAAA;  // grey
      default:    return 12'hF0F;  // broken map
    endcase
  endfunction

  // Unpassable tiles (ocean and mountain)
  function automatic logic is_walkable(input logic [TERRAIN_BITS-1:0] t);
    return (t != T_OCEAN) && (t != T_MOUNTAIN);
  endfunction

  // -------------------------------------------- MAP --------------------------------------------

  // Playable map: 32x20 tiles
  localparam int PLAY_TILES_X = 32;
  localparam int PLAY_TILES_Y = 20;

  // Map position on the 1280x800 screen: centred
  localparam int MAP_LEFT = (1280 - (PLAY_TILES_X << TILE_BITS)) / 2;  // 128
  localparam int MAP_TOP = (800 - (PLAY_TILES_Y << TILE_BITS)) / 2;  // 80

  // Player colors
  function automatic logic [11:0] player_color(input logic p);
    return p ? 12'h26F : 12'hE22;
  endfunction

  // One hardcoded city per player
  localparam logic [MAP_X_BITS-1:0] CITY_P1_X = 5'd4;
  localparam logic [MAP_Y_BITS-1:0] CITY_P1_Y = 5'd10;
  localparam logic [MAP_X_BITS-1:0] CITY_P2_X = 5'd27;
  localparam logic [MAP_Y_BITS-1:0] CITY_P2_Y = 5'd9;

  function automatic logic [MAP_X_BITS-1:0] city_x(input logic p);
    return p ? CITY_P2_X : CITY_P1_X;
  endfunction
  function automatic logic [MAP_Y_BITS-1:0] city_y(input logic p);
    return p ? CITY_P2_Y : CITY_P1_Y;
  endfunction

  // -------------------------------------------- UNITS --------------------------------------------

  // Units: a table of MAX_UNITS slots; a slot is empty when in_use = 0
  localparam int MAX_UNITS = 8;
  localparam int UNIT_INDEX_BITS = 3;
  localparam int MOVES_BITS = 3;
  localparam int HP_BITS = 4;
  localparam logic [HP_BITS-1:0] MAX_HP = 4'd10;  // largest HP = HP bar length

  // Unit types
  localparam logic [1:0] U_SPEARMAN = 2'd0;
  localparam logic [1:0] U_ARCHER = 2'd1;
  localparam logic [1:0] U_CAVALRY = 2'd2;

  typedef struct packed {
    logic                  in_use;        // slot holds a unit
    logic                  player_owner;  // 0 = Player 1, 1 = Player 2
    logic [1:0]            unit_type;     // U_SPEARMAN / U_ARCHER / U_CAVALRY
    logic [MAP_X_BITS-1:0] x;
    logic [MAP_Y_BITS-1:0] y;
    logic [MOVES_BITS-1:0] moves_left;    // movement points left this turn
    logic [HP_BITS-1:0]    hp;            // hit points left
  } unit;

  // Fighting
  localparam logic [HP_BITS-1:0] ATTACK_DAMAGE = 4'd3;
  function automatic logic [HP_BITS-1:0] counter_damage(input logic [1:0] attacker);
    return (attacker == U_ARCHER) ? 4'd0 : 4'd1;  // archers attack from range
  endfunction

  // Full HP per unit type
  function automatic logic [HP_BITS-1:0] max_hp(input logic [1:0] t);
    return (t == U_ARCHER) ? 4'd6 : MAX_HP;
  endfunction

  // Movement points per turn
  function automatic logic [MOVES_BITS-1:0] moves_per_turn(input logic [1:0] t);
    return (t == U_CAVALRY) ? 3'd4 : 3'd2;
  endfunction

  // New unit with full HP and moves
  function automatic unit new_unit(input logic player_owner, input logic [1:0] unit_type,
                                   input logic [MAP_X_BITS-1:0] x, input logic [MAP_Y_BITS-1:0] y);
    unit n;
    n.in_use       = 1'b1;
    n.player_owner = player_owner;
    n.unit_type    = unit_type;
    n.x            = x;
    n.y            = y;
    n.moves_left   = moves_per_turn(unit_type);
    n.hp           = max_hp(unit_type);
    return n;
  endfunction

  // Units at reset
  function automatic unit initial_unit(input int i);
    case (i)
      0:       return new_unit(1'b0, U_SPEARMAN, CITY_P1_X + 5'd1, CITY_P1_Y);  // east of city
      1:       return new_unit(1'b0, U_ARCHER, CITY_P1_X, CITY_P1_Y - 5'd1);  // north
      2:       return new_unit(1'b0, U_CAVALRY, CITY_P1_X, CITY_P1_Y + 5'd1);  // south
      3:       return new_unit(1'b1, U_SPEARMAN, CITY_P2_X - 5'd1, CITY_P2_Y);  // west of city
      4:       return new_unit(1'b1, U_ARCHER, CITY_P2_X + 5'd1, CITY_P2_Y);  // east
      5:       return new_unit(1'b1, U_CAVALRY, CITY_P2_X, CITY_P2_Y + 5'd1);  // south
      default: return '0;
    endcase
  endfunction

  // unit on tile (qx, qy): returns {found, index}; lowest index wins
  function automatic logic [UNIT_INDEX_BITS:0] find_unit(
    input unit [MAX_UNITS-1:0] u, input logic [MAP_X_BITS-1:0] qx, input logic [MAP_Y_BITS-1:0] qy);
    logic [UNIT_INDEX_BITS:0] r;
    r = '0;
    for (int i = MAX_UNITS - 1; i >= 0; i--) begin
      if (u[i].in_use && u[i].x == qx && u[i].y == qy) r = {1'b1, UNIT_INDEX_BITS'(i)};
    end
    return r;
  endfunction

  // Next unit of 'player' after slot 'last', wrapping around: returns {found, index}
  function automatic logic [UNIT_INDEX_BITS:0] find_next_own_unit(
    input unit [MAX_UNITS-1:0] u, input logic player, input logic [UNIT_INDEX_BITS-1:0] last);
    logic [  UNIT_INDEX_BITS:0] r;
    logic [UNIT_INDEX_BITS-1:0] idx;
    r = '0;
    for (int k = MAX_UNITS; k >= 1; k--) begin  // backwards, so the nearest slot wins
      idx = last + UNIT_INDEX_BITS'(k);
      if (u[idx].in_use && u[idx].player_owner == player) r = {1'b1, idx};
    end
    return r;
  endfunction

  // -------------------------------------------- SPRITES --------------------------------------------

  // Sprites: 16x16 pixels, drawn 2x; one 4-bit palette index per pixel.
  // Sprite number = unit type (0-2); the city is sprite 3.
  localparam int SPRITE_BITS = 4;  // 16 pixels
  localparam int PIXEL_BITS = 4;
  localparam int NUM_SPRITES = 4;
  localparam int SPRITE_ADDR_BITS = 2 + 2 * SPRITE_BITS;  // {sprite, row, column}
  localparam logic [1:0] SPRITE_CITY = 2'd3;

  // Palette (as in scripts/gen_sprites.py); 0 = transparent, 2/3 = owner colour
  function automatic logic [11:0] sprite_color(input logic [PIXEL_BITS-1:0] i, input logic [11:0] owner);
    case (i)
      4'h1:    return 12'h111;  // outline
      4'h2:    return owner;
      4'h3:    return (owner >> 1) & 12'h777;  // dark owner colour
      4'h4:    return 12'hFFF;  // white
      4'h5:    return 12'hFC9;  // skin
      4'h6:    return 12'h963;  // wood
      4'h7:    return 12'h631;  // dark wood
      4'h8:    return 12'hCCC;  // steel / stone
      4'h9:    return 12'h888;  // dark steel / stone
      default: return 12'h000;  // transparent
    endcase
  endfunction

  // -------------------------------------------- BUTTONS --------------------------------------------

  // Button positions in the press[] vector
  localparam int NUM_BUTTONS = 5;
  localparam int BTN_CENTER = 0;
  localparam int BTN_UP = 1;
  localparam int BTN_DOWN = 2;
  localparam int BTN_LEFT = 3;
  localparam int BTN_RIGHT = 4;

endpackage
/* verilator lint_on UNUSEDPARAM */
