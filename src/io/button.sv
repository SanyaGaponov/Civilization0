// One push button: skip bouncing, one pulse per press.
module button #(
  parameter int LOOK_BITS = 20  // look every 2^20 clocks (~12.6 ms)
) (
  input  logic clk,
  input  logic rst,
  input  logic pressed_signal,  // from the pin, 1 = held down
  output logic pressed_finally  // 1 for one clock per press
);

  // Look at the button only when the timer wraps to 0.
  // Bouncing is shorter than the time between looks.
  // Only now_seen reads the pin; the press is decided one clock later,
  // when now_seen has settled.
  logic [LOOK_BITS-1:0] timer;
  logic                 now_seen;  // value at the latest look
  logic                 last_seen;  // value at the look before
  always_ff @(posedge clk) begin
    if (rst) begin
      timer           <= '0;
      now_seen        <= 1'b0;
      last_seen       <= 1'b0;
      pressed_finally <= 1'b0;
    end else begin
      timer           <= timer + 1'b1;
      pressed_finally <= 1'b0;
      if (timer == '0) begin
        now_seen  <= pressed_signal;
        last_seen <= now_seen;
      end
      if (timer == LOOK_BITS'(1)) pressed_finally <= now_seen & ~last_seen;  // down now, up before: new press
    end
  end

endmodule
