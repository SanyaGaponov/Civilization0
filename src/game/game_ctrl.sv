// Game rules: cursor, unit selection, movement and turns.
module game_ctrl
  import game_pkg::*;
(
  input  logic                       clk,
  input  logic                       rst,
  input  logic [NUM_BUTTONS-1:0]     press,
  // terrain map
  output logic [MAP_ADDR_BITS-1:0]   target_terrain_addr,
  input  logic [TERRAIN_BITS-1:0]    target_terrain,
  // game state, read by the renderer
  output tile_x_t                    cursor_x,
  output tile_y_t                    cursor_y,
  output player_t                    current_player,
  output logic                       unit_selected,
  output logic [UNIT_INDEX_BITS-1:0] selected_unit,
  output unit_t [MAX_UNITS-1:0]      unit_table
);

  typedef enum logic { S_PLAY, S_END_TURN } state_e;
  state_e state;

  localparam unit_t P1_START_UNIT = initial_unit(0);   // cursor starts on this unit

  // ---- target: one tile from the cursor (a selected unit is always under the cursor) ----
  tile_x_t target_x;
  tile_y_t target_y;
  logic    arrow_pressed, target_on_screen;

  always_comb begin
    target_x         = cursor_x;
    target_y         = cursor_y;
    target_on_screen = 1'b1;
    arrow_pressed    = press[BTN_UP] | press[BTN_DOWN] | press[BTN_LEFT] | press[BTN_RIGHT];
    if (press[BTN_UP]) begin
      if (cursor_y == '0) target_on_screen = 1'b0;
      else                target_y = cursor_y - 1'b1;
    end else if (press[BTN_DOWN]) begin
      if (cursor_y == tile_y_t'(SCREEN_TILES_Y - 1)) target_on_screen = 1'b0;
      else                                           target_y = cursor_y + 1'b1;
    end else if (press[BTN_LEFT]) begin
      if (cursor_x == '0) target_on_screen = 1'b0;
      else                target_x = cursor_x - 1'b1;
    end else if (press[BTN_RIGHT]) begin
      if (cursor_x == tile_x_t'(SCREEN_TILES_X - 1)) target_on_screen = 1'b0;
      else                                           target_x = cursor_x + 1'b1;
    end
  end

  // terrain at the target tile (no delay)
  assign target_terrain_addr = {target_y, target_x};

  // ---- questions about the board (combinational) ------------------------
  logic [UNIT_INDEX_BITS:0] unit_at_cursor, unit_at_target;   // {found, index}
  assign unit_at_cursor = find_unit(unit_table, cursor_x, cursor_y);
  assign unit_at_target = find_unit(unit_table, target_x, target_y);

  logic cursor_on_city;
  assign cursor_on_city = (cursor_x == CITY_P1_X && cursor_y == CITY_P1_Y) ||
                          (cursor_x == CITY_P2_X && cursor_y == CITY_P2_Y);

  logic target_is_enemy_city;
  assign target_is_enemy_city = (target_x == city_x(~current_player)) &&
                                (target_y == city_y(~current_player));

  logic can_move;   // the selected unit may step onto the target
  assign can_move = target_on_screen && is_walkable(target_terrain) &&
                    !unit_at_target[UNIT_INDEX_BITS] && !target_is_enemy_city;

  // Do any of the current player's OTHER units (not the selected one) have points left?
  logic other_units_can_move;
  always_comb begin
    other_units_can_move = 1'b0;
    for (int i = 0; i < MAX_UNITS; i++)
      if (unit_table[i].in_use && unit_table[i].owner == current_player &&
          unit_table[i].moves_left != '0 &&
          !(unit_selected && UNIT_INDEX_BITS'(i) == selected_unit))
        other_units_can_move = 1'b1;
  end

  // Where the cursor goes when the next player starts: their first unit, else their city.
  tile_x_t next_player_start_x;
  tile_y_t next_player_start_y;
  always_comb begin
    next_player_start_x = city_x(~current_player);
    next_player_start_y = city_y(~current_player);
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (unit_table[i].in_use && unit_table[i].owner == ~current_player) begin
        next_player_start_x = unit_table[i].x;
        next_player_start_y = unit_table[i].y;
      end
  end

  // ---- state machine -------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state          <= S_PLAY;
      current_player <= 1'b0;
      unit_selected  <= 1'b0;
      selected_unit  <= '0;
      for (int i = 0; i < MAX_UNITS; i++) unit_table[i] <= initial_unit(i);
      cursor_x       <= P1_START_UNIT.x;
      cursor_y       <= P1_START_UNIT.y;
    end else begin
      case (state)
        S_PLAY: begin
          if (!unit_selected) begin // cursor mode
            if (arrow_pressed) begin
              if (target_on_screen) begin
                cursor_x <= target_x;
                cursor_y <= target_y;
              end
            end else if (press[BTN_CENTER]) begin
              if (unit_at_cursor[UNIT_INDEX_BITS]) begin
                // a unit is here: select it if it's ours and can still move
                if (unit_table[unit_at_cursor[UNIT_INDEX_BITS-1:0]].owner == current_player &&
                    unit_table[unit_at_cursor[UNIT_INDEX_BITS-1:0]].moves_left != '0) begin
                  unit_selected <= 1'b1;
                  selected_unit <= unit_at_cursor[UNIT_INDEX_BITS-1:0];
                end
              end else if (!cursor_on_city) begin
                state <= S_END_TURN;              // empty tile: end turn early
              end
              // (centre on a city does nothing yet: reserved for building units)
            end
          end else begin
            // ---- unit selected ----
            if (press[BTN_CENTER]) begin
              unit_selected <= 1'b0;
            end else if (arrow_pressed && can_move) begin
              unit_table[selected_unit].x          <= target_x;
              unit_table[selected_unit].y          <= target_y;
              unit_table[selected_unit].moves_left <= unit_table[selected_unit].moves_left - 1'b1;
              cursor_x <= target_x;
              cursor_y <= target_y;
              if (unit_table[selected_unit].moves_left == 2'd1) begin   // this was its last point
                unit_selected <= 1'b0;
                if (!other_units_can_move) state <= S_END_TURN;
              end
            end
            // a blocked move does nothing
          end
        end

        S_END_TURN: begin
          current_player <= ~current_player;
          unit_selected  <= 1'b0;
          for (int i = 0; i < MAX_UNITS; i++)
            if (unit_table[i].in_use && unit_table[i].owner == ~current_player)
              unit_table[i].moves_left <= moves_per_turn(unit_table[i].kind);
          cursor_x <= next_player_start_x;
          cursor_y <= next_player_start_y;
          state    <= S_PLAY;
        end

        default: state <= S_PLAY;
      endcase
    end
  end

endmodule
