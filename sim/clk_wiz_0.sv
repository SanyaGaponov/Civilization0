// Simulation-only stand-in for the Clocking Wizard IP: passes the clock through.
module clk_wiz_0 (
  input  logic clk_in1,
  output logic clk_out1,
  output logic locked
);
  assign clk_out1 = clk_in1;
  assign locked   = 1'b1;
endmodule
