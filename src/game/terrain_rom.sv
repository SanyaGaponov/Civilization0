// Terrain map ROM: 64x32 tiles, 4 bits each, two combinational read ports.
module terrain_rom
  import game_pkg::*;
#(
  parameter string INIT_FILE = "map0.mem"
)(
  input  logic [MAP_ADDR_W-1:0] addr_a,
  output logic [TERRAIN_W-1:0]  data_a,
  input  logic [MAP_ADDR_W-1:0] addr_b,
  output logic [TERRAIN_W-1:0]  data_b
);

  (* rom_style = "distributed" *)
  logic [TERRAIN_W-1:0] mem [MAP_W * MAP_H];

  initial $readmemh(INIT_FILE, mem);

  assign data_a = mem[addr_a];
  assign data_b = mem[addr_b];

endmodule
