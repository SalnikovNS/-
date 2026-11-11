module kuz_keyexp (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    input  wire          clear,
    input  wire [255:0]  key,
    output reg  [1279:0] rk,
    output reg           ready,
    output reg           busy
);
`include "kuz_rcon.vh"

    reg [127:0] a, b;
    reg [5:0]   step;
    wire [127:0] f;

    kuz_round u_f (.x(a), .k(kuz_rcon(step)), .y(f));

    always @(posedge clk) begin
        if (rst || clear) begin
            rk    <= 1280'h0;
            a     <= 128'h0;
            b     <= 128'h0;
            step  <= 6'd0;
            ready <= 1'b0;
            busy  <= 1'b0;
        end else if (start) begin
            a     <= key[255:128];
            b     <= key[127:0];
            rk    <= {key, 1024'h0};
            step  <= 6'd1;
            ready <= 1'b0;
            busy  <= 1'b1;
        end else if (busy) begin

            a <= f ^ b;
            b <= a;
            step <= step + 1'b1;

            if (step[2:0] == 3'd0) begin

                case (step[5:3])
                    3'd1: rk[1023:768] <= {f ^ b, a};
                    3'd2: rk[767:512]  <= {f ^ b, a};
                    3'd3: rk[511:256]  <= {f ^ b, a};
                    3'd4: rk[255:0]    <= {f ^ b, a};
                    default: ;
                endcase
                if (step == 6'd32) begin
                    busy  <= 1'b0;
                    ready <= 1'b1;
                    a     <= 128'h0;
                    b     <= 128'h0;
                end
            end
        end
    end
endmodule
