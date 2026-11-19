// Screen test: run game_top for one frame, check the VGA signal and the picture, save it.
// Options: +KEYS=CRU (buttons to press first: C U D L R), +OUT=frame.ppm
/* verilator lint_off BLKSEQ */
module tb_screen;
  import game_pkg::*;

  parameter string MAP_FILE = "map.mem";
  parameter string SPRITE_FILE = "sprites.mem";

  // 1280x800 timing, as in vga_out; counted from the start of vsync
  localparam int H_SYNC = 136;
  localparam int H_START = 336;  // first visible pixel
  localparam int H_TOTAL = 1680;
  localparam int V_SYNC = 3;
  localparam int V_START = 27;  // first visible line
  localparam int V_TOTAL = 828;
  localparam int WIDTH = 1280;
  localparam int HEIGHT = 800;

  localparam int TILE = 32;
  localparam int HOLD = (1 << 20) + 16;  // longer than one button look

  // Board pins
  logic       clk;
  logic       rst_n;
  logic [4:0] btn;  // {R, L, D, U, C}
  logic [3:0] r, g, b;
  logic hsync, vsync;

  // ~83 MHz clock
  initial begin
    clk = 1'b0;
    forever #6 clk = ~clk;
  end

  /* verilator lint_off PINCONNECTEMPTY */
  game_top #(
    .MAP_FILE   (MAP_FILE),
    .SPRITE_FILE(SPRITE_FILE)
  ) dut (
    .clk       (clk),
    .CPU_RESETN(rst_n),
    .BTNC      (btn[0]),
    .BTNU      (btn[1]),
    .BTND      (btn[2]),
    .BTNL      (btn[3]),
    .BTNR      (btn[4]),
    .SW        (1'b0),
    .pix_r     (r),
    .pix_g     (g),
    .pix_b     (b),
    .hsync     (hsync),
    .vsync     (vsync),
    .LED       (),
    .CA        (),
    .CB        (),
    .CC        (),
    .CD        (),
    .CE        (),
    .CF        (),
    .CG        (),
    .DP        (),
    .AN        ()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // The map the screen should show
  logic [TERRAIN_BITS-1:0] map[MAP_WIDTH*MAP_HEIGHT];
  initial $readmemh(MAP_FILE, map);

  int errors = 0;
  task automatic error(input string msg);
    errors++;
    if (errors <= 10) $display("ERROR: %s", msg);
  endtask

  // Hold one button, then release it
  task automatic press(input byte key);
    case (key)
      "C": btn = 5'b00001;
      "U": btn = 5'b00010;
      "D": btn = 5'b00100;
      "L": btn = 5'b01000;
      "R": btn = 5'b10000;
      default: begin
        $display("ignoring unknown key '%c'", key);
        return;
      end
    endcase
    repeat (HOLD) @(posedge clk);
    btn = '0;
    repeat (HOLD) @(posedge clk);
  endtask

  // The captured picture
  logic [11:0] frame[HEIGHT][WIDTH];

  // One whole frame, clock by clock: check sync and blanking, store visible pixels
  task automatic capture_frame();
    logic visible;
    @(posedge vsync);  // frame starts: line 0, pixel 0
    for (int v = 0; v < V_TOTAL; v++) begin
      for (int h = 0; h < H_TOTAL; h++) begin
        #1;  // let the outputs settle after the clock edge
        if (hsync != (h >= H_SYNC)) error($sformatf("hsync wrong at line %0d, pixel %0d", v, h));
        if (vsync != (v < V_SYNC)) error($sformatf("vsync wrong at line %0d, pixel %0d", v, h));
        visible = (h >= H_START) && (h < H_START + WIDTH) && (v >= V_START) && (v < V_START + HEIGHT);
        if (visible) frame[v-V_START][h-H_START] = {r, g, b};
        else if ({r, g, b} != '0) error($sformatf("colour during blanking at line %0d, pixel %0d", v, h));
        @(posedge clk);
      end
    end
  endtask

  // Outside the map: black
  task automatic check_border();
    logic on_map;
    for (int y = 0; y < HEIGHT; y++) begin
      for (int x = 0; x < WIDTH; x++) begin
        on_map = (x >= MAP_LEFT) && (x < MAP_LEFT + PLAY_TILES_X * TILE) &&
                 (y >= MAP_TOP) && (y < MAP_TOP + PLAY_TILES_Y * TILE);
        if (!on_map && frame[y][x] != '0) error($sformatf("not black around the map at (%0d, %0d)", x, y));
      end
    end
  endtask

  // Every tile: right terrain, units, cities and cursor
  task automatic check_tiles();
    int x0, y0;
    logic [   MAP_X_BITS-1:0] tile_x;
    logic [   MAP_Y_BITS-1:0] tile_y;
    logic [UNIT_INDEX_BITS:0] unit_here;  // {found, index}
    logic city_here, cursor_here, city_owner, found_owner_color, wrong_terrain;
    // cursor frame colour
    logic [11:0] cursor_color;
    for (int ty = 0; ty < PLAY_TILES_Y; ty++) begin
      for (int tx = 0; tx < PLAY_TILES_X; tx++) begin
        tile_x       = MAP_X_BITS'(tx);
        tile_y       = MAP_Y_BITS'(ty);
        x0           = MAP_LEFT + tx * TILE;  // tile's top-left pixel
        y0           = MAP_TOP + ty * TILE;
        unit_here    = find_unit(dut.unit_table, tile_x, tile_y);
        city_owner   = (tile_x == CITY_P2_X && tile_y == CITY_P2_Y);
        city_here    = city_owner || (tile_x == CITY_P1_X && tile_y == CITY_P1_Y);
        cursor_here  = (tile_x == dut.cursor_x && tile_y == dut.cursor_y);
        cursor_color = player_color(dut.current_player);

        // empty tile: every pixel has the map's terrain colour
        if (!unit_here[UNIT_INDEX_BITS] && !city_here && !cursor_here) begin
          wrong_terrain = 1'b0;
          for (int y = 0; y < TILE; y++) begin
            for (int x = 0; x < TILE; x++) begin
              if (frame[y0+y][x0+x] != terrain_color(map[ty*MAP_WIDTH+tx])) wrong_terrain = 1'b1;
            end
          end
          if (wrong_terrain) error($sformatf("tile (%0d, %0d): wrong terrain colour", tx, ty));
        end

        // unit: first HP segment is green (HP >= 1)
        if (unit_here[UNIT_INDEX_BITS] && frame[y0+28][x0+6] != 12'h0F0)
          error($sformatf("tile (%0d, %0d): unit without HP bar", tx, ty));

        // city without a unit on it: drawn in its owner's colour
        if (city_here && !unit_here[UNIT_INDEX_BITS]) begin
          found_owner_color = 1'b0;
          for (int y = 0; y < TILE; y++) begin
            for (int x = 0; x < TILE; x++) begin
              if (frame[y0+y][x0+x] == player_color(city_owner)) found_owner_color = 1'b1;
            end
          end
          if (!found_owner_color) error($sformatf("tile (%0d, %0d): city not drawn", tx, ty));
        end

        // cursor: frame corners in the current player's colour
        if (cursor_here && (frame[y0][x0] != cursor_color || frame[y0+TILE-1][x0+TILE-1] != cursor_color))
          error($sformatf("tile (%0d, %0d): cursor frame missing", tx, ty));
      end
    end
  endtask

  // Binary PPM: header, then 3 bytes (R, G, B) per pixel
  task automatic save_ppm(input string path);
    int          f;
    logic [11:0] c;
    f = $fopen(path, "wb");
    $fwrite(f, "P6\n%0d %0d\n255\n", WIDTH, HEIGHT);
    for (int y = 0; y < HEIGHT; y++) begin
      for (int x = 0; x < WIDTH; x++) begin
        c = frame[y][x];
        $fwrite(f, "%c%c%c", 8'(c[11:8] * 17), 8'(c[7:4] * 17), 8'(c[3:0] * 17));  // 4 -> 8 bits
      end
    end
    $fclose(f);
    $display("wrote %s", path);
  endtask

  initial begin
    string keys, out;
    if (!$value$plusargs("KEYS=%s", keys)) keys = "";
    if (!$value$plusargs("OUT=%s", out)) out = "frame.ppm";

    btn   = '0;
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;

    for (int i = 0; i < keys.len(); i++) press(keys[i]);
    capture_frame();
    check_border();
    check_tiles();
    save_ppm(out);

    if (errors == 0)
      $display("PASS: tb_screen (sync timing, blanking, border, terrain, units, cities, cursor)");
    else $display("FAIL: tb_screen, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
