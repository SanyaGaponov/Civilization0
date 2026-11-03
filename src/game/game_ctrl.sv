// game_ctrl.sv - game state and rules: cursor, units, turns, movement.
//
// Controls (one press = one action):
//   no unit selected : arrows move the cursor (stops at the map edge)
//                      centre on your unit (with moves left) -> select it
//                      centre on an empty tile (no unit, no city) -> end turn
//   unit selected    : arrows move the unit one tile, if allowed
//                      centre -> deselect
// A move is allowed if the target is on the map, passable terrain (not ocean
// or mountain), has no unit (fighting comes later) and is not the enemy city.
// Each move costs 1 point; at 0 the unit is deselected, and when none of the
// player's units have points left the turn passes automatically.
//
// State machine:
//   S_IDLE       wait for a button press
//   S_WAIT       terrain ROM is reading the target tile (1 clock latency)
//   S_CHECK      apply the movement rules, move the unit if allowed
//   S_AFTER_MOVE deselect / auto end turn when points run out
//   S_END_TURN   switch player, refill points, jump the cursor
module game_ctrl
  import game_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst,
  input  logic [NUM_BTN-1:0]      press,       // 1-clock pulses from buttons.sv
  // terrain ROM, port A (read only)
  output logic [MAP_ADDR_W-1:0]   terr_addr,
  input  logic [TERRAIN_W-1:0]    terr_data,
  // game state, read by the renderer
  output tile_x_t                 cursor_x,
  output tile_y_t                 cursor_y,
  output player_t                 cur_player,
  output logic                    sel_valid,
  output logic [UNIT_IDX_W-1:0]   sel_idx,
  output unit_t [MAX_UNITS-1:0]   units
);

  typedef enum logic [2:0] { S_IDLE, S_WAIT, S_CHECK, S_AFTER_MOVE, S_END_TURN } state_e;
  localparam unit_t START0 = start_unit(0);    // Player 1's first unit (cursor starts there)
  state_e state;

  tile_x_t tgt_x;   // tile the selected unit wants to move to
  tile_y_t tgt_y;
  assign terr_addr = {tgt_y, tgt_x};

  // ---- one step from the cursor (or from the selected unit) -------------
  tile_x_t base_x, step_x;
  tile_y_t base_y, step_y;
  logic    arrow, in_bounds;

  always_comb begin
    base_x    = sel_valid ? units[sel_idx].x : cursor_x;
    base_y    = sel_valid ? units[sel_idx].y : cursor_y;
    step_x    = base_x;
    step_y    = base_y;
    in_bounds = 1'b1;
    arrow     = press[BTN_U] | press[BTN_D] | press[BTN_L] | press[BTN_R];
    if (press[BTN_U]) begin
      if (base_y == '0) in_bounds = 1'b0; else step_y = base_y - 1'b1;
    end else if (press[BTN_D]) begin
      if (base_y == tile_y_t'(PLAY_H - 1)) in_bounds = 1'b0; else step_y = base_y + 1'b1;
    end else if (press[BTN_L]) begin
      if (base_x == '0) in_bounds = 1'b0; else step_x = base_x - 1'b1;
    end else if (press[BTN_R]) begin
      if (base_x == tile_x_t'(PLAY_W - 1)) in_bounds = 1'b0; else step_x = base_x + 1'b1;
    end
  end

  // ---- questions about the board (combinational) ------------------------
  logic [UNIT_IDX_W:0] at_cursor, at_target;   // {found, index}
  assign at_cursor = find_unit(units, cursor_x, cursor_y);
  assign at_target = find_unit(units, tgt_x, tgt_y);

  logic cursor_on_city;
  assign cursor_on_city = (cursor_x == CITY0_X && cursor_y == CITY0_Y) ||
                          (cursor_x == CITY1_X && cursor_y == CITY1_Y);

  logic target_is_enemy_city;
  assign target_is_enemy_city = (tgt_x == city_x(~cur_player)) && (tgt_y == city_y(~cur_player));

  logic own_moves_left;   // does the current player have any unit with points left?
  always_comb begin
    own_moves_left = 1'b0;
    for (int i = 0; i < MAX_UNITS; i++)
      if (units[i].valid && units[i].owner == cur_player && units[i].moves != '0)
        own_moves_left = 1'b1;
  end

  // Where the cursor goes when the next player starts: their first unit, else their city.
  tile_x_t next_start_x;
  tile_y_t next_start_y;
  always_comb begin
    next_start_x = city_x(~cur_player);
    next_start_y = city_y(~cur_player);
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (units[i].valid && units[i].owner == ~cur_player) begin
        next_start_x = units[i].x;
        next_start_y = units[i].y;
      end
  end

  // ---- state machine -------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state      <= S_IDLE;
      cur_player <= 1'b0;
      sel_valid  <= 1'b0;
      sel_idx    <= '0;
      tgt_x      <= '0;
      tgt_y      <= '0;
      for (int i = 0; i < MAX_UNITS; i++) units[i] <= start_unit(i);
      cursor_x   <= START0.x;                  // start on Player 1's unit
      cursor_y   <= START0.y;
    end else begin
      case (state)
        S_IDLE: begin
          if (!sel_valid) begin
            if (arrow) begin
              if (in_bounds) begin
                cursor_x <= step_x;
                cursor_y <= step_y;
              end
            end else if (press[BTN_C]) begin
              if (at_cursor[UNIT_IDX_W]) begin
                // a unit is here: select it if it's ours and can still move
                if (units[at_cursor[UNIT_IDX_W-1:0]].owner == cur_player &&
                    units[at_cursor[UNIT_IDX_W-1:0]].moves != '0) begin
                  sel_valid <= 1'b1;
                  sel_idx   <= at_cursor[UNIT_IDX_W-1:0];
                end
              end else if (!cursor_on_city) begin
                state <= S_END_TURN;              // empty tile: end turn early
              end
              // (centre on a city does nothing yet: reserved for building units)
            end
          end else begin
            if (press[BTN_C]) begin
              sel_valid <= 1'b0;
            end else if (arrow && in_bounds) begin
              tgt_x <= step_x;
              tgt_y <= step_y;
              state <= S_WAIT;
            end
          end
        end

        S_WAIT: state <= S_CHECK;                 // ROM now reads terrain at target

        S_CHECK: begin
          if (passable(terr_data) && !at_target[UNIT_IDX_W] && !target_is_enemy_city) begin
            units[sel_idx].x     <= tgt_x;
            units[sel_idx].y     <= tgt_y;
            units[sel_idx].moves <= units[sel_idx].moves - 1'b1;
            cursor_x <= tgt_x;
            cursor_y <= tgt_y;
            state    <= S_AFTER_MOVE;
          end else begin
            state <= S_IDLE;                      // not allowed: nothing happens
          end
        end

        S_AFTER_MOVE: begin
          if (units[sel_idx].moves == '0) begin
            sel_valid <= 1'b0;
            state     <= own_moves_left ? S_IDLE : S_END_TURN;
          end else begin
            state <= S_IDLE;
          end
        end

        S_END_TURN: begin
          cur_player <= ~cur_player;
          sel_valid  <= 1'b0;
          for (int i = 0; i < MAX_UNITS; i++)
            if (units[i].valid && units[i].owner == ~cur_player)
              units[i].moves <= unit_moves(units[i].utype);
          cursor_x <= next_start_x;
          cursor_y <= next_start_y;
          state    <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
