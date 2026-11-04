// One push button: make it safe for our clock, skip bouncing, one pulse per press.
module button #(
  parameter int SLOW_W = 20      // look at the button every 2^SLOW_W clocks (~12.6 ms)
)(
  input  logic clk,
  input  logic rst,
  input  logic raw,              // straight from the pin, 1 = held down
  output logic press             // 1 for one clock when the button goes down
);

  // 1. Two flip-flops in a row: the pin can change at any moment,
  //    sync2 is a clean 0 or 1 aligned to our clock.
  logic sync1, sync2;
  always_ff @(posedge clk) begin
    sync1 <= raw;
    sync2 <= sync1;
  end

  // 2. Look at the button only when the timer wraps to 0.
  //    Bouncing lasts a few ms, less than the time between looks,
  //    so one press is never seen as two.
  logic [SLOW_W-1:0] timer;
  logic              last;       // what we saw at the previous look
  always_ff @(posedge clk) begin
    if (rst) begin
      timer <= '0;
      last  <= 1'b0;
      press <= 1'b0;
    end else begin
      timer <= timer + 1'b1;
      press <= 1'b0;
      if (timer == '0) begin
        press <= sync2 & ~last;  // down now, up last time: a new press
        last  <= sync2;
      end
    end
  end

endmodule
