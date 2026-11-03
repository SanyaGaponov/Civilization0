// tb_game_ctrl.sv - checks game_ctrl against a reference model.
//
// The testbench contains its own simple, software-style copy of the rules
// (the "model"). It sends thousands of random button presses to both the
// hardware (game_ctrl + the real terrain ROM) and the model, and after every
// press compares cursor, current player, selection and the whole unit table.
// Coverage counters at the end prove that every rule was actually exercised
// (moves, blocked by terrain / unit / enemy city / screen edge, both kinds of
// turn end, ...).
`timescale 1ns/1ps

// Testbench style: blocking "=" in processes is intentional.
/* verilator lint_off BLKSEQ */
module tb_game_ctrl;
  import game_pkg::*;

  parameter string MAP_FILE = "map0.mem";
  localparam int N_PRESSES = 20000;

  logic clk, rst;
  initial begin clk = 1'b0; rst = 1'b1; end
  always #5 clk = ~clk;

  // ---- design under test -----------------------------------------------------
  logic [NUM_BTN-1:0]    press;
  logic [MAP_ADDR_W-1:0] terr_addr;
  logic [TERRAIN_W-1:0]  terr_data;
  tile_x_t               cursor_x;
  tile_y_t               cursor_y;
  player_t               cur_player;
  logic                  sel_valid;
  logic [UNIT_IDX_W-1:0] sel_idx;
  unit_t [MAX_UNITS-1:0] units;

  /* verilator lint_off PINCONNECTEMPTY */
  terrain_rom #(.INIT_FILE(MAP_FILE)) u_rom (
    .clk(clk), .addr_a(terr_addr), .data_a(terr_data), .addr_b('0), .data_b());
  /* verilator lint_on PINCONNECTEMPTY */

  game_ctrl dut (.clk(clk), .rst(rst), .press(press), .terr_addr(terr_addr),
                 .terr_data(terr_data), .cursor_x(cursor_x), .cursor_y(cursor_y),
                 .cur_player(cur_player), .sel_valid(sel_valid), .sel_idx(sel_idx),
                 .units(units));

  // ---- reference model ------------------------------------------------------
  logic [TERRAIN_W-1:0] map [MAP_W * MAP_H];
  int  m_x [MAX_UNITS], m_y [MAX_UNITS], m_moves [MAX_UNITS];
  bit  m_valid [MAX_UNITS], m_owner [MAX_UNITS];
  bit  m_player, m_sel;
  int  m_sidx, m_cx, m_cy;

  int errors;
  // coverage counters
  int n_cursor, n_cursor_edge, n_select, n_deselect, n_move, n_blk_terrain,
      n_blk_unit, n_blk_city, n_blk_edge, n_turn_manual, n_turn_auto, n_c_city;

  function automatic int unit_at(int x, int y);
    for (int i = 0; i < MAX_UNITS; i++)
      if (m_valid[i] && m_x[i] == x && m_y[i] == y) return i;
    return -1;
  endfunction

  function automatic int city_at(int x, int y);   // -1, 0 (Player 1) or 1 (Player 2)
    if (x == int'(CITY0_X) && y == int'(CITY0_Y)) return 0;
    if (x == int'(CITY1_X) && y == int'(CITY1_Y)) return 1;
    return -1;
  endfunction

  task automatic model_reset();
    for (int i = 0; i < MAX_UNITS; i++) begin
      unit_t u = start_unit(i);
      m_valid[i] = u.valid; m_owner[i] = u.owner;
      m_x[i] = int'(u.x); m_y[i] = int'(u.y); m_moves[i] = int'(u.moves);
      if (u.valid && u.utype != U_SPEARMAN) begin
        errors++; $display("ERROR: starter unit %0d is not a spearman", i);
      end
    end
    m_player = 0; m_sel = 0; m_sidx = 0;
    m_cx = m_x[0]; m_cy = m_y[0];
  endtask

  task automatic model_end_turn();
    m_player = !m_player;
    m_sel    = 0;
    m_cx = int'(city_x(m_player)); m_cy = int'(city_y(m_player));
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (m_valid[i] && m_owner[i] == m_player) begin
        m_moves[i] = 1;                    // spearmen only, for now
        m_cx = m_x[i]; m_cy = m_y[i];      // cursor -> first own unit
      end
  endtask

  task automatic model_press(int b);
    int bx, by, nx, ny, u;
    bit ok, left;
    if (b == BTN_C) begin
      if (m_sel) begin
        m_sel = 0; n_deselect++;
      end else begin
        u = unit_at(m_cx, m_cy);
        if (u >= 0) begin
          if (m_owner[u] == m_player && m_moves[u] > 0) begin m_sel = 1; m_sidx = u; n_select++; end
        end else if (city_at(m_cx, m_cy) >= 0) begin
          n_c_city++;                        // reserved for city menu: nothing happens
        end else begin
          model_end_turn(); n_turn_manual++;
        end
      end
      return;
    end
    bx = m_sel ? m_x[m_sidx] : m_cx;
    by = m_sel ? m_y[m_sidx] : m_cy;
    nx = bx; ny = by;
    case (b)
      BTN_U: ny = by - 1;
      BTN_D: ny = by + 1;
      BTN_L: nx = bx - 1;
      default: nx = bx + 1;
    endcase
    ok = (nx >= 0) && (nx < PLAY_W) && (ny >= 0) && (ny < PLAY_H);
    if (!m_sel) begin
      if (ok) begin m_cx = nx; m_cy = ny; n_cursor++; end else n_cursor_edge++;
      return;
    end
    if (!ok)                                       begin n_blk_edge++;    return; end
    if (!passable(map[ny * MAP_W + nx]))           begin n_blk_terrain++; return; end
    if (unit_at(nx, ny) >= 0)                      begin n_blk_unit++;    return; end
    if (city_at(nx, ny) == int'(!m_player))        begin n_blk_city++;    return; end
    m_x[m_sidx] = nx; m_y[m_sidx] = ny; m_moves[m_sidx]--;
    m_cx = nx; m_cy = ny; n_move++;
    if (m_moves[m_sidx] == 0) begin
      m_sel = 0;
      left = 0;
      for (int i = 0; i < MAX_UNITS; i++)
        if (m_valid[i] && m_owner[i] == m_player && m_moves[i] > 0) left = 1;
      if (!left) begin model_end_turn(); n_turn_auto++; end
    end
  endtask

  // ---- compare hardware with model ------------------------------------------
  task automatic compare(int step);
    bit bad;
    bad = (int'(cursor_x) != m_cx) || (int'(cursor_y) != m_cy) ||
          (cur_player != m_player) || (sel_valid != m_sel) ||
          (m_sel && int'(sel_idx) != m_sidx);
    for (int i = 0; i < MAX_UNITS; i++) begin
      if (units[i].valid != m_valid[i]) bad = 1;
      if (m_valid[i] && (units[i].owner != m_owner[i] || int'(units[i].x) != m_x[i] ||
                         int'(units[i].y) != m_y[i]   || int'(units[i].moves) != m_moves[i]))
        bad = 1;
    end
    if (bad) begin
      errors++;
      if (errors <= 5)
        $display("ERROR after press %0d: HW cursor (%0d,%0d) player %0d sel %0d/%0d unit0 (%0d,%0d) m%0d unit1 (%0d,%0d) m%0d | MODEL cursor (%0d,%0d) player %0d sel %0d/%0d unit0 (%0d,%0d) m%0d unit1 (%0d,%0d) m%0d",
          step, cursor_x, cursor_y, cur_player, sel_valid, sel_idx,
          units[0].x, units[0].y, units[0].moves, units[1].x, units[1].y, units[1].moves,
          m_cx, m_cy, m_player, m_sel, m_sidx, m_x[0], m_y[0], m_moves[0], m_x[1], m_y[1], m_moves[1]);
    end
  endtask

  // deterministic pseudo-random numbers (xorshift32), same on every simulator
  logic [31:0] rnd;
  function automatic logic [31:0] xorshift(logic [31:0] s);
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
    return s;
  endfunction

  task automatic do_press(int b, int step);
    @(negedge clk) press = '0;
    press[b] = 1'b1;
    @(negedge clk) press = '0;
    repeat (8) @(negedge clk);            // let the state machine finish
    model_press(b);
    compare(step);
  endtask

  // step in x / y for an arrow button
  function automatic int dir_dx(int d);
    return (d == BTN_R) ? 1 : (d == BTN_L) ? -1 : 0;
  endfunction
  function automatic int dir_dy(int d);
    return (d == BTN_D) ? 1 : (d == BTN_U) ? -1 : 0;
  endfunction

  // ---- directed scenario: P1 walks to P2's city and bumps into it ------------
  // P2 passes every turn (moves the cursor to an empty tile, presses centre).
  task automatic p2_pass();
    int nx, ny;
    for (int d = BTN_U; d <= BTN_R; d++) begin
      nx = m_cx + dir_dx(d);
      ny = m_cy + dir_dy(d);
      if (nx >= 0 && nx < PLAY_W && ny >= 0 && ny < PLAY_H &&
          unit_at(nx, ny) < 0 && city_at(nx, ny) < 0) begin
        do_press(d, -1);
        do_press(BTN_C, -1);
        return;
      end
    end
  endtask

  task automatic directed_meet();
    int gx, gy, cx, cy, nx, ny, head, tail, n_path;
    int steps [MAP_W * MAP_H];
    int from_dir [MAP_W * MAP_H];
    int queue [MAP_W * MAP_H];
    int path [64];
    gx = int'(CITY1_X); gy = int'(CITY1_Y) - 1;        // tile just above P2's city
    // breadth-first search from P1's unit over passable, empty, non-city tiles
    for (int i = 0; i < MAP_W * MAP_H; i++) steps[i] = -1;
    head = 0; tail = 0;
    queue[tail] = m_y[0] * MAP_W + m_x[0]; tail++;
    steps[m_y[0] * MAP_W + m_x[0]] = 0;
    while (head < tail) begin
      cx = queue[head] % MAP_W; cy = queue[head] / MAP_W; head++;
      for (int d = BTN_U; d <= BTN_R; d++) begin
        nx = cx + dir_dx(d);
        ny = cy + dir_dy(d);
        if (nx >= 0 && nx < PLAY_W && ny >= 0 && ny < PLAY_H && steps[ny * MAP_W + nx] < 0 &&
            passable(map[ny * MAP_W + nx]) && unit_at(nx, ny) < 0 && city_at(nx, ny) < 0) begin
          steps[ny * MAP_W + nx]     = steps[cy * MAP_W + cx] + 1;
          from_dir[ny * MAP_W + nx] = d;
          queue[tail] = ny * MAP_W + nx; tail++;
        end
      end
    end
    if (steps[gy * MAP_W + gx] < 0 || steps[gy * MAP_W + gx] > 64) begin
      errors++; $display("ERROR: directed test: no path to (%0d,%0d)", gx, gy); return;
    end
    // walk back from the goal to recover the directions
    n_path = steps[gy * MAP_W + gx];
    cx = gx; cy = gy;
    for (int k = n_path - 1; k >= 0; k--) begin
      path[k] = from_dir[cy * MAP_W + cx];
      cx -= dir_dx(path[k]);
      cy -= dir_dy(path[k]);
    end
    $display("directed: P1 spearman walks %0d tiles to (%0d,%0d), next to P2's city", n_path, gx, gy);
    // one step per turn: select + move (turn ends automatically), then P2 passes
    for (int k = 0; k < n_path; k++) begin
      do_press(BTN_C, -1);
      do_press(path[k], -1);
      p2_pass();
    end
    // now at the goal: moving down = into P2's city -> must be refused
    do_press(BTN_C, -1);
    do_press(BTN_D, -1);                     // blocked by enemy city
    do_press(BTN_L, -1);                     // step left: now above P2's spearman
    p2_pass();
    do_press(BTN_C, -1);
    do_press(BTN_D, -1);                     // blocked by P2's unit
    do_press(BTN_C, -1);                     // deselect
    if (errors == 0) $display("directed: done, hardware matches the model");
  endtask

  initial begin
    int b, r;
    press = '0;
    errors = 0;
    rnd = 32'h1234_5678;
    $readmemh(MAP_FILE, map);
    n_cursor = 0; n_cursor_edge = 0; n_select = 0; n_deselect = 0; n_move = 0;
    n_blk_terrain = 0; n_blk_unit = 0; n_blk_city = 0; n_blk_edge = 0;
    n_turn_manual = 0; n_turn_auto = 0; n_c_city = 0;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    model_reset();
    @(negedge clk) compare(0);

    directed_meet();

    for (int step = 1; step <= N_PRESSES; step++) begin
      rnd = xorshift(rnd);
      r = int'(rnd % 100);
      // centre 15%, arrows 85%; arrows are biased per 2000-press "epoch" so
      // units wander far across the map and eventually meet.
      if (r < 15) b = BTN_C;
      else begin
        rnd = xorshift(rnd);
        b = 1 + int'(rnd % 4);
        if (rnd[7:6] == 2'b00) b = 1 + ((step / 2000) % 4);
      end
      do_press(b, step);
    end

    $display("coverage: cursor moves %0d, cursor at edge %0d, selects %0d, deselects %0d,",
             n_cursor, n_cursor_edge, n_select, n_deselect);
    $display("          unit moves %0d, blocked by terrain %0d / unit %0d / enemy city %0d / edge %0d,",
             n_move, n_blk_terrain, n_blk_unit, n_blk_city, n_blk_edge);
    $display("          turn ends manual %0d / auto %0d, centre on city %0d",
             n_turn_manual, n_turn_auto, n_c_city);
    if (n_cursor == 0 || n_cursor_edge == 0 || n_select == 0 || n_deselect == 0 || n_move == 0 ||
        n_blk_terrain == 0 || n_blk_unit == 0 || n_blk_city == 0 ||
        n_turn_manual == 0 || n_turn_auto == 0) begin
      errors++;
      $display("ERROR: some rules were never exercised (see coverage above)");
    end
    if (errors == 0) $display("PASS: tb_game_ctrl, %0d random presses match the reference model", N_PRESSES);
    else             $display("FAIL: tb_game_ctrl, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
