// One push button: synchronize, skip bouncing, one pulse per press.
module button #(
  parameter int LOOK_BITS = 20                 // look every 2^20 clocks (~12.6 ms)
)(
  input  logic clk,
  input  logic rst,
  input  logic pressed_signal,                 // from the pin, 1 = held down
  output logic pressed_finally                 // 1 for one clock per press
);

  // Two flip-flops: make the pin safe for our clock
  logic sync1, sync2;
  always_ff @(posedge clk) begin
    sync1 <= pressed_signal;
    sync2 <= sync1;
  end

  // Look at the button only when the timer wraps to 0.
  // Bouncing is shorter than the time between looks.
  logic [LOOK_BITS-1:0] timer;
  logic                 last_seen;   // value at the previous look
  always_ff @(posedge clk) begin
    if (rst) begin
      timer           <= '0;
      last_seen       <= 1'b0;
      pressed_finally <= 1'b0;
    end else begin
      timer           <= timer + 1'b1;
      pressed_finally <= 1'b0;
      if (timer == '0) begin
        pressed_finally <= sync2 & ~last_seen;  // down now, up before: new press
        last_seen       <= sync2;
      end
    end
  end

endmodule
