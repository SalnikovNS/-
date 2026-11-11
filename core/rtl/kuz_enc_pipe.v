module kuz_enc_pipe (
    input  wire          clk,
    input  wire [1279:0] rk,
    input  wire          v_in,
    input  wire [127:0]  d_in,
    output wire          v_out,
    output wire [127:0]  d_out
);
    localparam integer LATENCY = 10;

    reg [127:0] st [0:9];
    reg [9:0]   vld = 10'b0;

    wire [127:0] rnd_out [0:8];

    genvar r;
    generate
        for (r = 0; r < 9; r = r + 1) begin : g_round

            kuz_round u_round (
                .x ((r == 0) ? d_in : st[r-1]),
                .k (rk[1279 - 128*r -: 128]),
                .y (rnd_out[r])
            );
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        vld <= {vld[8:0], v_in};
        for (i = 0; i < 9; i = i + 1)
            st[i] <= rnd_out[i];
        st[9] <= st[8] ^ rk[127:0];
    end

    assign v_out = vld[9];
    assign d_out = st[9];
endmodule
