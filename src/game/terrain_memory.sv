// Terrain map memory (read-only): 64x32 tiles, 4 bits each, two instant reads.
module terrain_memory
  import game_pkg::*;
#(
  parameter string MAP_FILE = "map0.mem"
)(
  input  logic [MAP_ADDR_BITS-1:0] game_addr,   // read for game_ctrl
  output logic [TERRAIN_BITS-1:0]  game_data,
  input  logic [MAP_ADDR_BITS-1:0] draw_addr,   // read for drawcon
  output logic [TERRAIN_BITS-1:0]  draw_data
);

  logic [TERRAIN_BITS-1:0] tiles [MAP_WIDTH * MAP_HEIGHT];

  initial $readmemh(MAP_FILE, tiles);

  assign game_data = tiles[game_addr];
  assign draw_data = tiles[draw_addr];

endmodule
