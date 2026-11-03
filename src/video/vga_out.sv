// VGA controller: counters, sync pulses, blanking, current pixel position.
module vga_out (
  input  logic        clk,      // pixel clock, 83.46 MHz
  input  logic        rst,
  input  logic [3:0]  r,
  input  logic [3:0]  g,
  input  logic [3:0]  b,
  output logic [3:0]  pix_r,
  output logic [3:0]  pix_g,
  output logic [3:0]  pix_b,
  output logic        hsync,
  output logic        vsync,
  output logic [10:0] curr_x,
  output logic [9:0]  curr_y
);

  // ---- screen timing: 1280x800 at 60 Hz -------------------------------------
  //   hcount: 0..135 sync | 136..335 back porch | 336..1615 visible | 1616..1679 front porch
  //   vcount: 0..2   sync | 3..26    back porch | 27..826   visible | 827        front porch
  localparam logic [10:0] H_SYNC   = 11'd136;
  localparam logic [10:0] H_BP     = 11'd200;
  localparam logic [10:0] H_ACTIVE = 11'd1280;
  localparam logic [10:0] H_FP     = 11'd64;
  localparam logic [10:0] H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;   // 1680
  localparam logic [10:0] H_START  = H_SYNC + H_BP;                     // 336

  localparam logic [9:0]  V_SYNC   = 10'd3;
  localparam logic [9:0]  V_BP     = 10'd24;
  localparam logic [9:0]  V_ACTIVE = 10'd800;
  localparam logic [9:0]  V_FP     = 10'd1;
  localparam logic [9:0]  V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;   // 828
  localparam logic [9:0]  V_START  = V_SYNC + V_BP;                     // 27

  logic [10:0] hcount;
  logic [9:0]  vcount;

  // ---- counters ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      hcount <= '0;
      vcount <= '0;
    end else if (hcount == H_TOTAL - 1'b1) begin
      hcount <= '0;
      vcount <= (vcount == V_TOTAL - 1'b1) ? '0 : vcount + 1'b1;
    end else begin
      hcount <= hcount + 1'b1;
    end
  end

  assign hsync = (hcount < H_SYNC) ? 1'b0 : 1'b1;
  assign vsync = (vcount < V_SYNC) ? 1'b1 : 1'b0;

  logic visible;
  assign visible = (hcount >= H_START) && (hcount < H_START + H_ACTIVE) &&
                   (vcount >= V_START) && (vcount < V_START + V_ACTIVE);

  assign curr_x = hcount - H_START;
  assign curr_y = vcount - V_START;

  assign pix_r = visible ? r : 4'h0;
  assign pix_g = visible ? g : 4'h0;
  assign pix_b = visible ? b : 4'h0;

endmodule
