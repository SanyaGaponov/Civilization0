// Sprite pixels (read-only): 4 sprites of 16x16, 4-bit palette index each.
module sprite_memory
  import game_pkg::*;
#(
  parameter string SPRITE_FILE = "sprites.mem"
) (
  input  logic [SPRITE_ADDR_BITS-1:0] unit_addr,   // read for units
  output logic [      PIXEL_BITS-1:0] unit_pixel,
  input  logic [SPRITE_ADDR_BITS-1:0] city_addr,   // read for cities
  output logic [      PIXEL_BITS-1:0] city_pixel
);

  logic [PIXEL_BITS-1:0] pixels[NUM_SPRITES * (1 << (2 * SPRITE_BITS))];  // {sprite, y, x}

  initial $readmemh(SPRITE_FILE, pixels);

  assign unit_pixel = pixels[unit_addr];
  assign city_pixel = pixels[city_addr];

endmodule
