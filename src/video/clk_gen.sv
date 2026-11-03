// clk_gen.sv - makes the pixel clock and a clean reset for it.
//
// On the FPGA: uses the MMCM (dedicated clock-generator hardware) to turn the
// board's 100 MHz into the pixel clock, and puts it on a global clock buffer
// (BUFG) so it reaches every flip-flop at the same time.
// In Verilator simulation the Xilinx primitives don't exist, so the input
// clock is simply passed through (the simulator doesn't care about MHz).
module clk_gen
  import game_pkg::*;
(
  input  logic clk_100m,   // board oscillator
  input  logic rst_btn_n,  // CPU_RESETN button, active low, asynchronous
  output logic clk_pix,    // pixel clock
  output logic rst_pix,    // reset, synchronous to clk_pix, active high
  output logic locked      // 1 when the MMCM output is stable
);

`ifdef VERILATOR
  assign clk_pix = clk_100m;
  assign locked  = 1'b1;
`else
  logic clk_fb, clk_fb_buf, clk_pix_unbuf;

  MMCME2_BASE #(
    .CLKIN1_PERIOD    (10.0),          // 100 MHz input
    .DIVCLK_DIVIDE    (MMCM_DIV),
    .CLKFBOUT_MULT_F  (MMCM_MULT),
    .CLKOUT0_DIVIDE_F (MMCM_OUT_DIV)
  ) u_mmcm (
    .CLKIN1   (clk_100m),
    .CLKFBIN  (clk_fb_buf),
    .CLKFBOUT (clk_fb),
    .CLKOUT0  (clk_pix_unbuf),
    .LOCKED   (locked),
    .RST      (1'b0),
    .PWRDWN   (1'b0),
    // unused outputs
    .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(),
    .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
  );

  BUFG u_bufg_fb  (.I(clk_fb),        .O(clk_fb_buf));
  BUFG u_bufg_pix (.I(clk_pix_unbuf), .O(clk_pix));
`endif

  // Reset synchronizer ("asynchronous assert, synchronous release").
  // Reset turns ON immediately whenever the button is pressed or the clock
  // is not yet stable (locked = 0), including at power-up. It turns OFF
  // only after 2 clean clock edges, so every flip-flop leaves reset on the
  // same edge (no metastability from the button, which is not aligned to clk_pix).
  logic       rst_in_n;
  logic [1:0] rst_sync;
  assign rst_in_n = rst_btn_n & locked;

  always_ff @(posedge clk_pix or negedge rst_in_n) begin
    if (!rst_in_n) rst_sync <= 2'b11;
    else           rst_sync <= {rst_sync[0], 1'b0};
  end
  assign rst_pix = rst_sync[1];

endmodule
