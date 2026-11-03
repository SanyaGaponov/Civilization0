// Buttons: synchronize, debounce, one-clock pulse per press.
module buttons #(
  parameter int N     = 5,
  parameter int CNT_W = 20
)(
  input  logic         clk,
  input  logic         rst,
  input  logic [N-1:0] raw,     // straight from the pins, active high
  output logic [N-1:0] press    // 1-clock pulse per press
);

  logic [N-1:0] sync1, sync2;   // synchronizer stages
  logic [N-1:0] stable;         // debounced level
  logic [N-1:0] stable_q;       // stable, one clock later (for edge detect)
  logic [CNT_W-1:0] cnt [N];    // how long the input has differed from 'stable'

  always_ff @(posedge clk) begin
    sync1 <= raw;
    sync2 <= sync1;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      stable   <= '0;
      stable_q <= '0;
      for (int i = 0; i < N; i++) cnt[i] <= '0;
    end else begin
      for (int i = 0; i < N; i++) begin
        if (sync2[i] == stable[i]) begin
          cnt[i] <= '0;                       // no change: restart the timer
        end else if (&cnt[i]) begin
          stable[i] <= sync2[i];              // different for long enough: accept
          cnt[i]    <= '0;
        end else begin
          cnt[i] <= cnt[i] + 1'b1;
        end
      end
      stable_q <= stable;
    end
  end

  assign press = stable & ~stable_q;

endmodule
