// Testbench: game_ctrl vs. a reference model (directed and random presses).
`timescale 1ns / 1ps

// Blocking "=" in processes is intentional here.
/* verilator lint_off BLKSEQ */
module tb_game_ctrl;
  import game_pkg::*;

  parameter string MAP_FILE = "map.mem";
  localparam int N_PRESSES = 20000;

  logic clk, rst;
  initial begin
    clk = 1'b0;
    rst = 1'b1;
  end
  always #5 clk = ~clk;

  // Design under test
  logic [    NUM_BUTTONS-1:0] press;
  logic                       jump;
  logic [  MAP_ADDR_BITS-1:0] target_terrain_addr;
  logic [   TERRAIN_BITS-1:0] target_terrain;
  logic [     MAP_X_BITS-1:0] cursor_x;
  logic [     MAP_Y_BITS-1:0] cursor_y;
  logic                       current_player;
  logic                       unit_selected;
  logic [UNIT_INDEX_BITS-1:0] selected_unit;
  unit  [      MAX_UNITS-1:0] unit_table;

  /* verilator lint_off PINCONNECTEMPTY */
  terrain_memory #(
    .MAP_FILE(MAP_FILE)
  ) u_terrain (
    .game_addr(target_terrain_addr),
    .game_data(target_terrain),
    .draw_addr('0),
    .draw_data()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  game_ctrl dut (
    .clk                (clk),
    .rst                (rst),
    .press              (press),
    .jump               (jump),
    .target_terrain_addr(target_terrain_addr),
    .target_terrain     (target_terrain),
    .cursor_x           (cursor_x),
    .cursor_y           (cursor_y),
    .current_player     (current_player),
    .unit_selected      (unit_selected),
    .selected_unit      (selected_unit),
    .unit_table         (unit_table)
  );

  // Reference model
  logic [TERRAIN_BITS-1:0] map[MAP_WIDTH * MAP_HEIGHT];
  int m_x[MAX_UNITS], m_y[MAX_UNITS], m_moves[MAX_UNITS], m_hp[MAX_UNITS];
  bit m_valid[MAX_UNITS], m_player_owner[MAX_UNITS];
  logic [1:0] m_unit_type[MAX_UNITS];
  bit m_player, m_sel;
  int m_sidx, m_cx, m_cy;

  int errors;

  function automatic int unit_at(int x, int y);
    for (int i = 0; i < MAX_UNITS; i++) if (m_valid[i] && m_x[i] == x && m_y[i] == y) return i;
    return -1;
  endfunction

  function automatic int city_at(int x, int y);  // -1, 0 (Player 1) or 1 (Player 2)
    if (x == int'(CITY_P1_X) && y == int'(CITY_P1_Y)) return 0;
    if (x == int'(CITY_P2_X) && y == int'(CITY_P2_Y)) return 1;
    return -1;
  endfunction

  localparam int P1_SPEARMAN = 0;  // slots used by the directed tests
  localparam int P2_SPEARMAN = 3;

  task automatic model_reset();
    for (int i = 0; i < MAX_UNITS; i++) begin
      unit u = initial_unit(i);
      m_valid[i]        = u.in_use;
      m_player_owner[i] = u.player_owner;
      m_unit_type[i]    = u.unit_type;
      m_x[i]            = int'(u.x);
      m_y[i]            = int'(u.y);
      m_moves[i]        = int'(u.moves_left);
      m_hp[i]           = int'(u.hp);
    end
    if (m_unit_type[P1_SPEARMAN] != U_SPEARMAN || m_unit_type[P2_SPEARMAN] != U_SPEARMAN) begin
      errors++;
      $display("ERROR: directed tests expect spearmen in slots %0d and %0d", P1_SPEARMAN, P2_SPEARMAN);
    end
    m_player = 0;
    m_sel    = 0;
    m_sidx   = 0;
    m_cx     = m_x[0];
    m_cy     = m_y[0];
  endtask

  task automatic model_end_turn();
    m_player = !m_player;
    m_sel    = 0;
    m_cx     = int'(city_x(m_player));
    m_cy     = int'(city_y(m_player));
    for (int i = MAX_UNITS - 1; i >= 0; i--)
      if (m_valid[i] && m_player_owner[i] == m_player) begin
        m_moves[i] = int'(moves_per_turn(m_unit_type[i]));
        m_cx       = m_x[i];
        m_cy       = m_y[i];  // cursor -> first own unit
      end
  endtask

  task automatic model_remove(int u);  // defeated: slot becomes empty
    for (int i = 0; i < MAX_UNITS; i++)
      if (i == u) begin
        m_valid[i]        = 0;
        m_player_owner[i] = 0;
        m_x[i]            = 0;
        m_y[i]            = 0;
        m_moves[i]        = 0;
        m_hp[i]           = 0;
        m_unit_type[i]    = U_SPEARMAN;
      end
  endtask

  task automatic model_press(int b);
    int bx, by, nx, ny, u, c;
    bit ok, left;
    if (b == BTN_CENTER) begin
      if (m_sel) begin
        m_sel = 0;
      end else begin
        u = unit_at(m_cx, m_cy);
        if (u >= 0) begin
          if (m_player_owner[u] == m_player && m_moves[u] > 0) begin
            m_sel  = 1;
            m_sidx = u;
          end
        end else if (city_at(m_cx, m_cy) < 0) begin
          model_end_turn();  // empty tile; a city does nothing yet
        end
      end
      return;
    end
    bx = m_sel ? m_x[m_sidx] : m_cx;
    by = m_sel ? m_y[m_sidx] : m_cy;
    nx = bx;
    ny = by;
    case (b)
      BTN_UP:   ny = by - 1;
      BTN_DOWN: ny = by + 1;
      BTN_LEFT: nx = bx - 1;
      default:  nx = bx + 1;
    endcase
    ok = (nx >= 0) && (nx < PLAY_TILES_X) && (ny >= 0) && (ny < PLAY_TILES_Y);
    if (!m_sel) begin
      if (ok) begin
        m_cx = nx;
        m_cy = ny;
      end
      return;
    end
    if (!ok) return;  // map edge
    u = unit_at(nx, ny);
    if (u >= 0 && m_player_owner[u] != m_player) begin  // attack
      if (m_hp[u] <= int'(ATTACK_DAMAGE)) model_remove(u);
      else m_hp[u] -= int'(ATTACK_DAMAGE);
      c = int'(counter_damage(m_unit_type[m_sidx]));
      if (m_hp[m_sidx] <= c) model_remove(m_sidx);
      else begin
        m_hp[m_sidx] -= c;
        m_moves[m_sidx] = 0;
      end
      m_sel = 0;
      left  = 0;
      for (int i = 0; i < MAX_UNITS; i++) begin
        if (m_valid[i] && m_player_owner[i] == m_player && m_moves[i] > 0) left = 1;
      end
      if (!left) model_end_turn();
      return;
    end
    if (!is_walkable(map[ny*MAP_WIDTH+nx])) return;  // ocean, mountain
    if (unit_at(nx, ny) >= 0) return;  // own unit
    if (city_at(nx, ny) == int'(!m_player)) return;  // enemy city
    m_x[m_sidx] = nx;
    m_y[m_sidx] = ny;
    m_moves[m_sidx]--;
    m_cx = nx;
    m_cy = ny;
    if (m_moves[m_sidx] == 0) begin
      m_sel = 0;
      left  = 0;
      for (int i = 0; i < MAX_UNITS; i++) begin
        if (m_valid[i] && m_player_owner[i] == m_player && m_moves[i] > 0) left = 1;
      end
      if (!left) model_end_turn();
    end
  endtask

  // Compare hardware with the model
  task automatic compare(int step);
    bit bad;
    bad = (int'(cursor_x) != m_cx) || (int'(cursor_y) != m_cy) ||
          (current_player != m_player) || (unit_selected != m_sel) ||
          (m_sel && int'(selected_unit) != m_sidx);
    for (int i = 0; i < MAX_UNITS; i++) begin
      if (unit_table[i].in_use != m_valid[i]) bad = 1;
      if (m_valid[i] && (unit_table[i].player_owner != m_player_owner[i] || int'(unit_table[i].x) != m_x[i] ||
                         int'(unit_table[i].y) != m_y[i]   || int'(unit_table[i].moves_left) != m_moves[i] ||
                         int'(unit_table[i].hp) != m_hp[i]))
        bad = 1;
    end
    if (bad) begin
      errors++;
      if (errors <= 5)
        $display(
          "ERROR after press %0d: HW cursor (%0d,%0d) player %0d sel %0d/%0d unit0 (%0d,%0d) m%0d unit1 (%0d,%0d) m%0d | MODEL cursor (%0d,%0d) player %0d sel %0d/%0d unit0 (%0d,%0d) m%0d unit1 (%0d,%0d) m%0d",
          step,
          cursor_x,
          cursor_y,
          current_player,
          unit_selected,
          selected_unit,
          unit_table[0].x,
          unit_table[0].y,
          unit_table[0].moves_left,
          unit_table[1].x,
          unit_table[1].y,
          unit_table[1].moves_left,
          m_cx,
          m_cy,
          m_player,
          m_sel,
          m_sidx,
          m_x[0],
          m_y[0],
          m_moves[0],
          m_x[1],
          m_y[1],
          m_moves[1]
        );
    end
  endtask

  // Repeatable random numbers (xorshift32)
  logic [31:0] rnd;
  function automatic logic [31:0] xorshift(logic [31:0] s);
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
  endfunction

  task automatic do_press(int b, int step);
    @(negedge clk) press = '0;
    press[b] = 1'b1;
    @(negedge clk) press = '0;
    repeat (8) @(negedge clk);  // let the design settle
    model_press(b);
    compare(step);
  endtask

  // x / y step of an arrow button
  function automatic int dir_dx(int d);
    return (d == BTN_RIGHT) ? 1 : (d == BTN_LEFT) ? -1 : 0;
  endfunction
  function automatic int dir_dy(int d);
    return (d == BTN_DOWN) ? 1 : (d == BTN_UP) ? -1 : 0;
  endfunction

  // Directed tests
  // pass_turn: move the cursor to an empty tile and press centre.
  // end_turn_if(p): pass if it is still player p's turn.
  task automatic pass_turn();
    int nx, ny;
    if (m_sel) do_press(BTN_CENTER, -1);  // deselect first
    for (int d = BTN_UP; d <= BTN_RIGHT; d++) begin
      nx = m_cx + dir_dx(d);
      ny = m_cy + dir_dy(d);
      if (nx >= 0 && nx < PLAY_TILES_X && ny >= 0 && ny < PLAY_TILES_Y && unit_at(
          nx, ny
        ) < 0 && city_at(
          nx, ny
        ) < 0) begin
        do_press(d, -1);
        do_press(BTN_CENTER, -1);
        return;
      end
    end
  endtask

  task automatic end_turn_if(int p);
    if (int'(m_player) == p) pass_turn();
  endtask

  // P1's spearman walks next to P2's; fight = 1: then attack until it dies
  task automatic directed_meet(input bit fight);
    int gx, gy, cx, cy, nx, ny, head, tail, n_path;
    int steps   [MAP_WIDTH * MAP_HEIGHT];
    int from_dir[MAP_WIDTH * MAP_HEIGHT];
    int queue   [MAP_WIDTH * MAP_HEIGHT];
    int path    [                    64];
    gx = int'(CITY_P2_X);
    gy = int'(CITY_P2_Y) - 1;  // tile just above P2's city
    // shortest path (BFS) over free land
    for (int i = 0; i < MAP_WIDTH * MAP_HEIGHT; i++) steps[i] = -1;
    head        = 0;
    tail        = 0;
    queue[tail] = m_y[0] * MAP_WIDTH + m_x[0];
    tail++;
    steps[m_y[0]*MAP_WIDTH+m_x[0]] = 0;
    while (head < tail) begin
      cx = queue[head] % MAP_WIDTH;
      cy = queue[head] / MAP_WIDTH;
      head++;
      for (int d = BTN_UP; d <= BTN_RIGHT; d++) begin
        nx = cx + dir_dx(d);
        ny = cy + dir_dy(d);
        if (nx >= 0 && nx < PLAY_TILES_X && ny >= 0 && ny < PLAY_TILES_Y && steps[ny * MAP_WIDTH + nx] < 0 &&
            is_walkable(
            map[ny*MAP_WIDTH+nx]
          ) && unit_at(
            nx, ny
          ) < 0 && city_at(
            nx, ny
          ) < 0) begin
          steps[ny*MAP_WIDTH+nx]    = steps[cy*MAP_WIDTH+cx] + 1;
          from_dir[ny*MAP_WIDTH+nx] = d;
          queue[tail]               = ny * MAP_WIDTH + nx;
          tail++;
        end
      end
    end
    if (steps[gy*MAP_WIDTH+gx] < 0 || steps[gy*MAP_WIDTH+gx] > 64) begin
      errors++;
      $display("ERROR: directed test: no path to (%0d,%0d)", gx, gy);
      return;
    end
    // directions, from the goal back to the start
    n_path = steps[gy*MAP_WIDTH+gx];
    cx     = gx;
    cy     = gy;
    for (int k = n_path - 1; k >= 0; k--) begin
      path[k] = from_dir[cy*MAP_WIDTH+cx];
      cx -= dir_dx(path[k]);
      cy -= dir_dy(path[k]);
    end
    $display("directed: P1 spearman walks %0d tiles to (%0d,%0d), next to P2's city", n_path, gx, gy);
    // one step per turn; P2 passes
    for (int k = 0; k < n_path; k++) begin
      do_press(BTN_CENTER, -1);
      do_press(path[k], -1);
      end_turn_if(0);
      pass_turn();
    end
    // at the goal: moving into P2's city must be refused
    do_press(BTN_CENTER, -1);
    do_press(BTN_DOWN, -1);  // blocked by enemy city
    do_press(BTN_LEFT, -1);  // step left: now above P2's spearman
    end_turn_if(0);
    pass_turn();  // P2 passes
    if (!fight) return;
    // attack P2's spearman (below): 10 HP, -3 per attack = 4 attacks
    for (int k = 0; k < 4; k++) begin
      do_press(BTN_CENTER, -1);  // select
      do_press(BTN_DOWN, -1);  // attack
      end_turn_if(0);
      if (k < 3) pass_turn();
    end
    if (unit_table[P2_SPEARMAN].in_use || m_valid[P2_SPEARMAN]) begin
      errors++;
      $display("ERROR: directed test: P2's spearman should be defeated");
    end
    if (unit_table[P1_SPEARMAN].hp != MAX_HP - 4'd4) begin
      errors++;
      $display("ERROR: directed test: P1's spearman has %0d HP, expected 6", unit_table[P1_SPEARMAN].hp);
    end
    if (errors == 0)
      $display("directed: done, P2's spearman defeated in 4 attacks, hardware matches the model");
  endtask

  // After directed_meet(0): P2 attacks 3 times (P1 HP 10 -> 1, P2 10 -> 7),
  // then P1 attacks and dies from the counter-attack (P2 HP 7 -> 4).
  task automatic directed_counter_kill();
    for (int k = 0; k < 3; k++) begin
      pass_turn();  // P1 passes
      do_press(BTN_CENTER, -1);  // P2 selects its spearman
      do_press(BTN_UP, -1);  // ... and attacks P1's
      end_turn_if(1);  // P2 ends its turn
    end
    do_press(BTN_CENTER, -1);  // P1 selects
    do_press(BTN_DOWN, -1);  // ... and attacks with 1 HP left
    if (unit_table[P1_SPEARMAN].in_use || m_valid[P1_SPEARMAN]) begin
      errors++;
      $display("ERROR: directed test: P1's spearman should die from the counter-attack");
    end
    if (unit_table[P2_SPEARMAN].hp != 4'd4) begin
      errors++;
      $display("ERROR: directed test: P2's spearman has %0d HP, expected 4", unit_table[P2_SPEARMAN].hp);
    end
    if (errors == 0)
      $display("directed: attacker with 1 HP dies from the counter-attack, hardware matches the model");
  endtask

  // After reset: P1 uses all moves; the turn must pass by itself.
  task automatic directed_auto_end();
    do_press(BTN_CENTER, -1);  // spearman (5,10) -> (7,10)
    repeat (2) do_press(BTN_RIGHT, -1);
    repeat (3) do_press(BTN_LEFT, -1);  // cursor to the archer (4,9)
    do_press(BTN_UP, -1);
    do_press(BTN_CENTER, -1);  // archer (4,9) -> (4,7)
    repeat (2) do_press(BTN_UP, -1);
    repeat (4) do_press(BTN_DOWN, -1);  // cursor to the cavalry (4,11)
    do_press(BTN_CENTER, -1);  // cavalry (4,11) -> (4,15)
    repeat (4) do_press(BTN_DOWN, -1);  // no moves left anywhere
    if (current_player != 1'b1) begin
      errors++;
      $display("ERROR: directed test: turn did not pass after all P1 units moved");
    end
    if (errors == 0)
      $display("directed: all P1 moves used (spearman 2, archer 2, cavalry 4), turn passed automatically");
  endtask

  task automatic restart();
    rst = 1'b1;
    repeat (2) @(negedge clk);
    rst = 1'b0;
    model_reset();
    @(negedge clk) compare(0);
  endtask

  initial begin
    int b, r;
    press  = '0;
    jump   = 1'b0;  // SW0 is not tested here
    errors = 0;
    rnd    = 32'h1234_5678;
    $readmemh(MAP_FILE, map);

    repeat (4) @(negedge clk);
    rst = 1'b0;
    model_reset();
    @(negedge clk) compare(0);

    directed_auto_end();  // turn ends automatically
    restart();
    directed_meet(1'b1);  // P1 defeats P2's spearman
    restart();
    directed_meet(1'b0);
    directed_counter_kill();  // attacker dies from the counter-attack
    // random presses, starting with the spearmen side by side
    restart();
    directed_meet(1'b0);

    for (int step = 1; step <= N_PRESSES; step++) begin
      rnd = xorshift(rnd);
      r   = int'(rnd % 100);
      // centre 15%, arrows 85%; direction bias changes every 2000 presses
      if (r < 15) b = BTN_CENTER;
      else begin
        rnd = xorshift(rnd);
        b   = 1 + int'(rnd % 4);
        if (rnd[7:6] == 2'b00) b = 1 + ((step / 2000) % 4);
      end
      do_press(b, step);
    end

    if (errors == 0) $display("PASS: tb_game_ctrl, %0d random presses match the reference model", N_PRESSES);
    else $display("FAIL: tb_game_ctrl, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
