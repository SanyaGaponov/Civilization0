// Eight seven segment digits on one set of segment wires.
//
// The board wires a-g to all eight digits and picks the digit with the
// (active low) anodes an[7:0], so only one digit can be lit at a time.
// This module shows one digit per 'tick' and walks through all eight; at
// roughly 600 ticks per second the eye sees all of them at once.
// Digits are numbered from the right: dig0 is the rightmost one.
module multidigit (
  input  logic       clk,
  input  logic       rst,
  input  logic       tick,  // step to the next digit
  input  logic [3:0] dig0,  // rightmost digit
  input  logic [3:0] dig1,
  input  logic [3:0] dig2,
  input  logic [3:0] dig3,
  input  logic [3:0] dig4,
  input  logic [3:0] dig5,
  input  logic [3:0] dig6,
  input  logic [3:0] dig7,
  input  logic [7:0] en,    // 0 = leave that digit dark
  output logic       a,     // segments a..g
  output logic       b,
  output logic       c,
  output logic       d,
  output logic       e,
  output logic       f,
  output logic       g,
  output logic [7:0] an
);

  // Which digit is driven right now
  logic [2:0] cnt;
  always_ff @(posedge clk) begin
    if (rst) cnt <= 3'd0;
    else if (tick) cnt <= cnt + 3'd1;
  end

  logic [3:0] num;
  always_comb begin
    case (cnt)
      3'd0:    num = dig0;
      3'd1:    num = dig1;
      3'd2:    num = dig2;
      3'd3:    num = dig3;
      3'd4:    num = dig4;
      3'd5:    num = dig5;
      3'd6:    num = dig6;
      3'd7:    num = dig7;
      default: num = dig0;
    endcase
    // Active low: pull just this digit's anode down, and only if it is shown
    an = en[cnt] ? ~(8'd1 << cnt) : 8'hFF;
  end

  sevenseg u_sevenseg (
    .num(num),
    .a  (a),
    .b  (b),
    .c  (c),
    .d  (d),
    .e  (e),
    .f  (f),
    .g  (g)
  );

endmodule
