// Terrain map memory (read-only): 64x32 tiles, 4 bits each, two instant reads.
module terrain_memory
  import game_pkg::*;
#(
  parameter string world_map_file = "map0.mem"
)(
  input  logic [MAP_ADDR_W-1:0] game_addr,   // read for game_ctrl
  output logic [TERRAIN_W-1:0]  game_data,
  input  logic [MAP_ADDR_W-1:0] draw_addr,   // read for drawcon
  output logic [TERRAIN_W-1:0]  draw_data
);

  logic [TERRAIN_W-1:0] mem [MAP_W * MAP_H];

  initial $readmemh(world_map_file, mem);

  assign game_data = mem[game_addr];
  assign draw_data = mem[draw_addr];

endmodule
