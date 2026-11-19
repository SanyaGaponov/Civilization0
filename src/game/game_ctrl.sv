module game_ctrl
  import game_pkg::*;
(
  input  logic                       clk,
  input  logic                       rst,
  input  logic [    NUM_BUTTONS-1:0] press,
  input  logic                       jump,                 // SW0 flipped
  // terrain lookup
  output logic [  MAP_ADDR_BITS-1:0] target_terrain_addr,
  input  logic [   TERRAIN_BITS-1:0] target_terrain,
  // game state, read by drawcon
  output logic [     MAP_X_BITS-1:0] cursor_x,
  output logic [     MAP_Y_BITS-1:0] cursor_y,
  output logic                       current_player,
  output logic                       unit_selected,
  output logic [UNIT_INDEX_BITS-1:0] selected_unit,
  output unit  [      MAX_UNITS-1:0] unit_table
);

  localparam logic S_PLAY = 1'b0;
  localparam logic S_END_TURN = 1'b1;
  logic state;

  localparam unit P1_START_UNIT = initial_unit(0);  // cursor starts here

  // target is the tile next to the cursor in the pressed direction.
  // a selected unit is always under the cursor.
  logic [MAP_X_BITS-1:0] target_x;
  logic [MAP_Y_BITS-1:0] target_y;
  logic arrow_pressed, target_on_map;

  always_comb begin
    target_x      = cursor_x;
    target_y      = cursor_y;
    target_on_map = 1'b1;
    arrow_pressed = press[BTN_UP] | press[BTN_DOWN] | press[BTN_LEFT] | press[BTN_RIGHT];
    if (press[BTN_UP]) begin
      if (cursor_y == '0) target_on_map = 1'b0;
      else target_y = cursor_y - 1'b1;
    end else if (press[BTN_DOWN]) begin
      if (cursor_y == MAP_Y_BITS'(PLAY_TILES_Y - 1)) target_on_map = 1'b0;
      else target_y = cursor_y + 1'b1;
    end else if (press[BTN_LEFT]) begin
      if (cursor_x == '0) target_on_map = 1'b0;
      else target_x = cursor_x - 1'b1;
    end else if (press[BTN_RIGHT]) begin
      if (cursor_x == MAP_X_BITS'(PLAY_TILES_X - 1)) target_on_map = 1'b0;
      else target_x = cursor_x + 1'b1;
    end
  end

  assign target_terrain_addr = {target_y, target_x};

  // Board checks
  logic [UNIT_INDEX_BITS:0] unit_at_cursor, unit_at_target;  // {found, index}
  assign unit_at_cursor = find_unit(unit_table, cursor_x, cursor_y);
  assign unit_at_target = find_unit(unit_table, target_x, target_y);

  logic cursor_on_city;
  assign cursor_on_city = (cursor_x == CITY_P1_X && cursor_y == CITY_P1_Y) ||
                          (cursor_x == CITY_P2_X && cursor_y == CITY_P2_Y);

  // The other player's city
  logic [MAP_X_BITS-1:0] enemy_city_x;
  logic [MAP_Y_BITS-1:0] enemy_city_y;
  assign enemy_city_x = city_x(~current_player);
  assign enemy_city_y = city_y(~current_player);

  logic target_is_enemy_city;
  assign target_is_enemy_city = (target_x == enemy_city_x) && (target_y == enemy_city_y);

  logic can_move;  // target is free land
  assign can_move = target_on_map && is_walkable(
    target_terrain
  ) && !unit_at_target[UNIT_INDEX_BITS] && !target_is_enemy_city;

  logic [UNIT_INDEX_BITS-1:0] defender;
  logic                       can_attack;
  assign defender = unit_at_target[UNIT_INDEX_BITS-1:0];
  assign can_attack = target_on_map && unit_at_target[UNIT_INDEX_BITS] &&
                      unit_table[defender].player_owner != current_player;

  logic [HP_BITS-1:0] attacker_damage;  // HP the selected unit loses when attacking
  assign attacker_damage = counter_damage(unit_table[selected_unit].unit_type);


  // Slot the cursor jumped to last time, and the next own unit after it
  logic [UNIT_INDEX_BITS-1:0] last_jump;
  logic [  UNIT_INDEX_BITS:0] next_own_unit;  // {found, index}
  assign next_own_unit = find_next_own_unit(unit_table, current_player, last_jump);

  // Any other own unit with moves left?
  logic other_units_can_move;
  always_comb begin
    other_units_can_move = 1'b0;
    for (int i = 0; i < MAX_UNITS; i++) begin
      if (unit_table[i].in_use && unit_table[i].player_owner == current_player &&
          unit_table[i].moves_left != '0 &&
          !(unit_selected && UNIT_INDEX_BITS'(i) == selected_unit))
        other_units_can_move = 1'b1;
    end
  end

  // Cursor start for the next player: their first unit, else their city
  logic [MAP_X_BITS-1:0] next_player_start_x;
  logic [MAP_Y_BITS-1:0] next_player_start_y;
  always_comb begin
    next_player_start_x = enemy_city_x;
    next_player_start_y = enemy_city_y;
    for (int i = MAX_UNITS - 1; i >= 0; i--) begin
      if (unit_table[i].in_use && unit_table[i].player_owner == ~current_player) begin
        next_player_start_x = unit_table[i].x;
        next_player_start_y = unit_table[i].y;
      end
    end
  end

  // states
  always_ff @(posedge clk) begin
    if (rst) begin
      state          <= S_PLAY;
      current_player <= 1'b0;
      unit_selected  <= 1'b0;
      selected_unit  <= '0;
      for (int i = 0; i < MAX_UNITS; i++) unit_table[i] <= initial_unit(i);
      cursor_x  <= P1_START_UNIT.x;
      cursor_y  <= P1_START_UNIT.y;
      last_jump <= UNIT_INDEX_BITS'(MAX_UNITS - 1);  // first flip starts at slot 0
    end else begin
      // a flip made while a unit is selected is simply lost, not remembered.
      case (state)
        S_PLAY: begin
          if (!unit_selected) begin  // cursor mode
            if (arrow_pressed) begin
              if (target_on_map) begin
                cursor_x <= target_x;
                cursor_y <= target_y;
              end
            end else if (press[BTN_CENTER]) begin
              if (unit_at_cursor[UNIT_INDEX_BITS]) begin
                // select own unit with moves left
                if (unit_table[unit_at_cursor[UNIT_INDEX_BITS-1:0]].player_owner == current_player &&
                    unit_table[unit_at_cursor[UNIT_INDEX_BITS-1:0]].moves_left != '0) begin
                  unit_selected <= 1'b1;
                  selected_unit <= unit_at_cursor[UNIT_INDEX_BITS-1:0];
                end
              end else if (!cursor_on_city) begin
                state <= S_END_TURN;  // empty tile: end turn
              end
              // city: nothing yet
            end else if (jump && next_own_unit[UNIT_INDEX_BITS]) begin
              // SW0 flipped: move the cursor onto the next own unit 
              cursor_x  <= unit_table[next_own_unit[UNIT_INDEX_BITS-1:0]].x;
              cursor_y  <= unit_table[next_own_unit[UNIT_INDEX_BITS-1:0]].y;
              last_jump <= next_own_unit[UNIT_INDEX_BITS-1:0];
            end
          end else begin
            // unit selected
            if (press[BTN_CENTER]) begin
              unit_selected <= 1'b0;
            end else if (arrow_pressed && can_move) begin
              // move: unit and cursor step to the target
              unit_table[selected_unit].x          <= target_x;
              unit_table[selected_unit].y          <= target_y;
              unit_table[selected_unit].moves_left <= unit_table[selected_unit].moves_left - 1'b1;
              cursor_x                             <= target_x;
              cursor_y                             <= target_y;
              if (unit_table[selected_unit].moves_left == 3'd1) begin  // last move used
                unit_selected <= 1'b0;
                if (!other_units_can_move) state <= S_END_TURN;
              end
            end else if (arrow_pressed && can_attack) begin
              // attack: nobody moves; a unit at 0 HP is removed
              if (unit_table[defender].hp <= ATTACK_DAMAGE) unit_table[defender] <= '0;
              else unit_table[defender].hp <= unit_table[defender].hp - ATTACK_DAMAGE;
              if (unit_table[selected_unit].hp <= attacker_damage) unit_table[selected_unit] <= '0;
              else begin
                unit_table[selected_unit].hp         <= unit_table[selected_unit].hp - attacker_damage;
                unit_table[selected_unit].moves_left <= '0;  // attack uses all moves
              end
              unit_selected <= 1'b0;
              if (!other_units_can_move) state <= S_END_TURN;
            end
            // blocked: nothing happens
          end
        end

        S_END_TURN: begin
          // switch player, refill their moves, cursor to their first unit
          current_player <= ~current_player;
          unit_selected  <= 1'b0;
          for (int i = 0; i < MAX_UNITS; i++) begin
            if (unit_table[i].in_use && unit_table[i].player_owner == ~current_player)
              unit_table[i].moves_left <= moves_per_turn(unit_table[i].unit_type);
          end
          cursor_x  <= next_player_start_x;
          cursor_y  <= next_player_start_y;
          last_jump <= UNIT_INDEX_BITS'(MAX_UNITS - 1);  // new player: start at slot 0
          state     <= S_PLAY;
        end

        default: state <= S_PLAY;
      endcase
    end
  end

endmodule
