module gf128_mul (
    input  wire         clk,
    input  wire [127:0] a,
    input  wire [127:0] b,
    output reg  [127:0] p
);
    localparam integer LATENCY = 2;

    reg [254:0] prod_c;
    reg [254:0] prod_r;
    reg [254:0] red;
    integer i, k;

    always @* begin
        prod_c = 255'h0;
        for (i = 0; i < 128; i = i + 1)
            if (b[i])
                prod_c = prod_c ^ ({127'h0, a} << i);
    end

    always @* begin
        red = prod_r;
        for (k = 254; k >= 128; k = k - 1) begin

            red[k - 121] = red[k - 121] ^ red[k];
            red[k - 126] = red[k - 126] ^ red[k];
            red[k - 127] = red[k - 127] ^ red[k];
            red[k - 128] = red[k - 128] ^ red[k];
        end
    end

    always @(posedge clk) begin
        prod_r <= prod_c;
        p      <= red[127:0];
    end
endmodule
