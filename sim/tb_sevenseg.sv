// Testbench: sevenseg (all 16 values, segments active low).
`timescale 1ns/1ps

// Blocking "=" in processes is intentional here.
/* verilator lint_off BLKSEQ */
module tb_sevenseg;

  logic [3:0] num;
  logic       a, b, c, d, e, f, g;
  int         errors;

  sevenseg dut (.num(num), .a(a), .b(b), .c(c), .d(d), .e(e), .f(f), .g(g));

  // The pattern each value must light up, as {a,b,c,d,e,f,g}
  function automatic logic [6:0] want(input logic [3:0] n);
    case (n)
      4'h0:    return 7'b0000001;   // 0
      4'h1:    return 7'b1001111;   // 1
      4'h2:    return 7'b0010010;   // 2
      4'h3:    return 7'b0000110;   // 3
      4'h4:    return 7'b1001100;   // 4
      4'h5:    return 7'b0100100;   // 5
      4'h6:    return 7'b0100000;   // 6
      4'h7:    return 7'b0001111;   // 7
      4'h8:    return 7'b0000000;   // 8
      4'h9:    return 7'b0000100;   // 9
      4'hA:    return 7'b0001000;   // A
      4'hB:    return 7'b1100000;   // b
      4'hC:    return 7'b0110001;   // C
      4'hD:    return 7'b1000010;   // d
      4'hE:    return 7'b0110000;   // E
      default: return 7'b0111000;   // F
    endcase
  endfunction

  initial begin
    errors = 0;

    for (int i = 0; i < 16; i++) begin
      num = 4'(i);
      #1;
      if ({a, b, c, d, e, f, g} !== want(4'(i))) begin
        errors++;
        $display("ERROR: num=%0h gave %b, expected %b",
                 i, {a, b, c, d, e, f, g}, want(4'(i)));
      end
      // a digit that lights nothing at all would be a dead decoder
      if ({a, b, c, d, e, f, g} === 7'b1111111) begin
        errors++;
        $display("ERROR: num=%0h lights no segment", i);
      end
    end

    if (errors == 0) $display("PASS: tb_sevenseg (16 patterns, active low)");
    else             $display("FAIL: tb_sevenseg, %0d errors", errors);
    $finish;
  end

endmodule
/* verilator lint_on BLKSEQ */
