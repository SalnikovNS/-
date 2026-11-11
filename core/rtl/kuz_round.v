module kuz_round (
    input  wire [127:0] x,
    input  wire [127:0] k,
    output wire [127:0] y
);
    wire [127:0] xk = x ^ k;
    wire [127:0] s;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_sbox
            kuz_sbox u_sbox (.a(xk[8*i +: 8]), .y(s[8*i +: 8]));
        end
    endgenerate

    kuz_lin u_lin (.x(s), .y(y));
endmodule
