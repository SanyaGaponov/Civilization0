// Game rules: cursor, unit selection, movement and turns.
module game_ctrl
  import game_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst,
  input  logic [NUM_BTN-1:0]      press,       // 1-clock pulses from buttons.sv
  // terrain map (game read of terrain_memory, combinational)
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

  typedef enum logic { S_PLAY, S_END_TURN } state_e;
  state_e state;

  localparam unit_t START0 = start_unit(0);    // Player 1's first unit (cursor starts there)

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

  // terrain at the tile we would step onto (no delay)
  assign terr_addr = {step_y, step_x};

  // ---- questions about the board (combinational) ------------------------
  logic [UNIT_IDX_W:0] at_cursor, at_step;   // {found, index}
  assign at_cursor = find_unit(units, cursor_x, cursor_y);
  assign at_step   = find_unit(units, step_x, step_y);

  logic cursor_on_city;
  assign cursor_on_city = (cursor_x == CITY0_X && cursor_y == CITY0_Y) ||
                          (cursor_x == CITY1_X && cursor_y == CITY1_Y);

  logic step_is_enemy_city;
  assign step_is_enemy_city = (step_x == city_x(~cur_player)) && (step_y == city_y(~cur_player));

  logic can_move;   // the selected unit may step onto (step_x, step_y)
  assign can_move = in_bounds && passable(terr_data) && !at_step[UNIT_IDX_W] && !step_is_enemy_city;

  // Do any of the current player's OTHER units (not the selected one) have points left?
  logic others_have_moves;
  always_comb begin
    others_have_moves = 1'b0;
    for (int i = 0; i < MAX_UNITS; i++)
      if (units[i].valid && units[i].owner == cur_player && units[i].moves != '0 &&
          !(sel_valid && UNIT_IDX_W'(i) == sel_idx))
        others_have_moves = 1'b1;
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
      state      <= S_PLAY;
      cur_player <= 1'b0;
      sel_valid  <= 1'b0;
      sel_idx    <= '0;
      for (int i = 0; i < MAX_UNITS; i++) units[i] <= start_unit(i);
      cursor_x   <= START0.x;
      cursor_y   <= START0.y;
    end else begin
      case (state)
        S_PLAY: begin
          if (!sel_valid) begin
            // ---- cursor mode ----
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
            // ---- unit selected ----
            if (press[BTN_C]) begin
              sel_valid <= 1'b0;
            end else if (arrow && can_move) begin
              units[sel_idx].x     <= step_x;
              units[sel_idx].y     <= step_y;
              units[sel_idx].moves <= units[sel_idx].moves - 1'b1;
              cursor_x <= step_x;
              cursor_y <= step_y;
              if (units[sel_idx].moves == 2'd1) begin   // this was its last point
                sel_valid <= 1'b0;
                if (!others_have_moves) state <= S_END_TURN;
              end
            end
            // a blocked move does nothing
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
          state    <= S_PLAY;
        end

        default: state <= S_PLAY;
      endcase
    end
  end

endmodule
