// sim_top.sv - Verilator wrapper around game_top.
// Exposes the timing constants so the C++ "virtual monitor" knows where the
// visible window is. It does NOT peek inside the design: like a real monitor,
// it only sees the VGA pins.
`default_nettype none

module sim_top
  import game_pkg::*;
#(
  parameter string MAP_FILE = "map0.mem"
)(
  input  wire         clk,
  input  wire         rst_n,
  output logic [3:0]  r, g, b,
  output logic        hs, vs,
  output logic [15:0] p_h_sync, p_h_bp, p_h_active, p_h_total,
  output logic [15:0] p_v_sync, p_v_bp, p_v_active, p_v_total,
  output logic        p_h_pol, p_v_pol
);

  /* verilator lint_off PINCONNECTEMPTY */
  game_top #(.MAP_FILE(MAP_FILE)) dut (
    .CLK100MHZ (clk),
    .CPU_RESETN(rst_n),
    .VGA_R(r), .VGA_G(g), .VGA_B(b),
    .VGA_HS(hs), .VGA_VS(vs),
    .LED()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign p_h_sync   = 16'(H_SYNC);
  assign p_h_bp     = 16'(H_BP);
  assign p_h_active = 16'(H_ACTIVE);
  assign p_h_total  = 16'(H_TOTAL);
  assign p_v_sync   = 16'(V_SYNC);
  assign p_v_bp     = 16'(V_BP);
  assign p_v_active = 16'(V_ACTIVE);
  assign p_v_total  = 16'(V_TOTAL);
  assign p_h_pol    = H_POL;
  assign p_v_pol    = V_POL;

endmodule

`default_nettype wire
