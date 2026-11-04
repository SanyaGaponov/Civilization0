// One push button: make it safe for our clock, skip bouncing, one pulse per press.
module button #(
  parameter int LOOK_BITS = 20
)(
  input  logic clk,
  input  logic rst,
  input  logic pressed_signal,  
  output logic pressed_finally
);

  // Adress bouncing here
  logic sync1, sync2;
  always_ff @(posedge clk) begin
    sync1 <= pressed_signal;
    sync2 <= sync1;
  end

  // 2. Look at the button only when the timer wraps to 0.
  //    Bouncing lasts a few ms, less than the time between looks,
  //    so one press is never seen as two.
  logic [LOOK_BITS-1:0] timer;
  logic                 last_seen;   // what we saw at the previous look
  always_ff @(posedge clk) begin
    if (rst) begin
      timer           <= '0;
      last_seen       <= 1'b0;
      pressed_finally <= 1'b0;
    end else begin
      timer           <= timer + 1'b1;
      pressed_finally <= 1'b0;
      if (timer == '0) begin
        pressed_finally <= sync2 & ~last_seen;  // down now, up last time: a new press
        last_seen       <= sync2;
      end
    end
  end

endmodule
