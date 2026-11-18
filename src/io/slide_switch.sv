// One slide switch: skip bouncing, one pulse per flip (either direction).
module slide_switch #(
  parameter int LOOK_BITS = 20                 // look every 2^20 clocks (~12.6 ms)
)(
  input  logic clk,
  input  logic rst,
  input  logic switch_signal,                  // from the pin
  output logic flipped                         // 1 for one clock per flip
);

  // Look at the switch only when the timer wraps to 0.
  // Bouncing is shorter than the time between looks.
  // Only now_seen reads the pin; the flip is decided one clock later,
  // when now_seen has settled.
  logic [LOOK_BITS-1:0] timer;
  logic                 now_seen;    // value at the latest look
  logic                 last_seen;   // value at the look before
  logic                 started;     // 0 until the first look: no flip at reset
  always_ff @(posedge clk) begin
    if (rst) begin
      timer     <= '0;
      now_seen  <= 1'b0;
      last_seen <= 1'b0;
      started   <= 1'b0;
      flipped   <= 1'b0;
    end else begin
      timer   <= timer + 1'b1;
      flipped <= 1'b0;
      if (timer == '0) begin
        now_seen  <= switch_signal;
        last_seen <= now_seen;
      end
      if (timer == LOOK_BITS'(1)) begin
        flipped <= started & (now_seen != last_seen);   // changed since the last look
        started <= 1'b1;
      end
    end
  end

endmodule
