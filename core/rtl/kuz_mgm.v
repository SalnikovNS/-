module kuz_mgm (
    input  wire          clk,
    input  wire          rst,

    input  wire [1279:0] rk,

    input  wire          start,
    input  wire [126:0]  icn,
    input  wire          decrypt,
    output wire          busy,

    input  wire          s_valid,
    output wire          s_ready,
    input  wire [127:0]  s_data,
    input  wire [4:0]    s_bytes,
    input  wire          s_aad,
    input  wire          s_last,

    output reg           m_valid,
    output reg  [127:0]  m_data,
    output reg  [4:0]    m_bytes,
    output reg           m_last,

    output reg           tag_valid,
    output reg  [127:0]  tag
);
    localparam integer LAT  = 10;
    localparam integer MLAT = 2;

    localparam [2:0] K_NONE = 3'd0,
                     K_INIT = 3'd1,
                     K_AAD  = 3'd2,
                     K_DATA = 3'd3,
                     K_LEN  = 3'd4,
                     K_TAG  = 3'd5;

    localparam [2:0] ST_IDLE = 3'd0,
                     ST_INIT = 3'd1,
                     ST_RUN  = 3'd2,
                     ST_LEN  = 3'd3,
                     ST_SUM  = 3'd4,
                     ST_TAG  = 3'd5;

    reg [2:0]   state;
    reg         dec_r;
    reg [127:0] y_ctr;
    reg [127:0] z_ctr;
    reg [31:0]  alen, clen;

    assign busy    = (state != ST_IDLE);
    assign s_ready = (state == ST_RUN);

    wire s_xfer = s_valid && s_ready;

    function [127:0] byte_mask;
        input [4:0] n;
        integer j;
        begin
            for (j = 0; j < 16; j = j + 1)
                byte_mask[127 - 8*j -: 8] = (j < n) ? 8'hFF : 8'h00;
        end
    endfunction

    reg          a_v, b_v;
    reg  [127:0] a_d, b_d;
    wire         a_vo, b_vo;
    wire [127:0] a_do, b_do;

    kuz_enc_pipe u_pipe_a (.clk(clk), .rk(rk), .v_in(a_v), .d_in(a_d), .v_out(a_vo), .d_out(a_do));
    kuz_enc_pipe u_pipe_b (.clk(clk), .rk(rk), .v_in(b_v), .d_in(b_d), .v_out(b_vo), .d_out(b_do));

    reg  [2:0]   dl_kind_in;
    reg  [127:0] dl_data_in;
    reg  [4:0]   dl_bytes_in;
    reg          dl_last_in;

    reg  [2:0]   dl_kind  [0:LAT-1];
    reg  [127:0] dl_data  [0:LAT-1];
    reg  [4:0]   dl_bytes [0:LAT-1];
    reg          dl_last  [0:LAT-1];

    wire [2:0]   o_kind  = dl_kind [LAT-1];
    wire [127:0] o_data  = dl_data [LAT-1];
    wire [4:0]   o_bytes = dl_bytes[LAT-1];
    wire         o_last  = dl_last [LAT-1];

    reg  [127:0] mul_a, mul_b;
    wire [127:0] mul_p;
    reg  [MLAT:0] mul_v;
    reg  [MLAT:0] mul_f;
    reg  [127:0] acc;

    gf128_mul u_mul (.clk(clk), .a(mul_a), .b(mul_b), .p(mul_p));

    wire [127:0] acc_next = acc ^ mul_p;

    always @* begin
        a_v = 1'b0;  a_d = 128'h0;
        b_v = 1'b0;  b_d = 128'h0;
        dl_kind_in  = K_NONE;
        dl_data_in  = 128'h0;
        dl_bytes_in = 5'd0;
        dl_last_in  = 1'b0;

        if (state == ST_IDLE && start) begin
            a_v = 1'b1;  a_d = {1'b0, icn};
            b_v = 1'b1;  b_d = {1'b1, icn};
            dl_kind_in = K_INIT;

        end else if (s_xfer) begin
            b_v = 1'b1;  b_d = z_ctr;
            a_v = !s_aad;
            a_d = y_ctr;
            dl_kind_in  = s_aad ? K_AAD : K_DATA;
            dl_data_in  = s_data & byte_mask(s_bytes);
            dl_bytes_in = s_bytes;
            dl_last_in  = s_last;

        end else if (state == ST_LEN) begin
            b_v = 1'b1;  b_d = z_ctr;
            dl_kind_in = K_LEN;

            dl_data_in = {29'h0, alen, 3'b000, 29'h0, clen, 3'b000};

        end else if (state == ST_SUM && mul_v[MLAT] && mul_f[MLAT]) begin
            a_v = 1'b1;  a_d = acc_next;
            dl_kind_in = K_TAG;
        end
    end

    wire [127:0] o_mask = byte_mask(o_bytes);
    wire [127:0] o_xor  = (o_data ^ a_do) & o_mask;

    wire [127:0] o_auth = (o_kind == K_DATA) ? (dec_r ? o_data : o_xor) : o_data;

    integer i;

    always @(posedge clk) begin

        dl_kind [0] <= dl_kind_in;
        dl_data [0] <= dl_data_in;
        dl_bytes[0] <= dl_bytes_in;
        dl_last [0] <= dl_last_in;
        for (i = 1; i < LAT; i = i + 1) begin
            dl_kind [i] <= dl_kind [i-1];
            dl_data [i] <= dl_data [i-1];
            dl_bytes[i] <= dl_bytes[i-1];
            dl_last [i] <= dl_last [i-1];
        end

        mul_a <= b_do;
        mul_b <= o_auth;
        mul_v <= {mul_v[MLAT-1:0], (o_kind == K_AAD) || (o_kind == K_DATA) || (o_kind == K_LEN)};
        mul_f <= {mul_f[MLAT-1:0], (o_kind == K_LEN)};

        m_valid   <= 1'b0;
        m_last    <= 1'b0;
        tag_valid <= 1'b0;

        if (rst) begin
            state   <= ST_IDLE;
            dec_r   <= 1'b0;
            y_ctr   <= 128'h0;
            z_ctr   <= 128'h0;
            alen    <= 32'd0;
            clen    <= 32'd0;
            acc     <= 128'h0;
            mul_v   <= {(MLAT+1){1'b0}};
            mul_f   <= {(MLAT+1){1'b0}};
            m_data  <= 128'h0;
            m_bytes <= 5'd0;
            tag     <= 128'h0;
            for (i = 0; i < LAT; i = i + 1)
                dl_kind[i] <= K_NONE;

        end else begin

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        dec_r <= decrypt;
                        alen  <= 32'd0;
                        clen  <= 32'd0;
                        acc   <= 128'h0;
                        state <= ST_INIT;
                    end
                end

                ST_INIT: begin
                    if (o_kind == K_INIT) begin
                        y_ctr <= a_do;
                        z_ctr <= b_do;
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (s_xfer) begin

                        z_ctr[127:64] <= z_ctr[127:64] + 1'b1;
                        if (s_aad) begin
                            alen <= alen + s_bytes;
                        end else begin
                            y_ctr[63:0] <= y_ctr[63:0] + 1'b1;
                            clen <= clen + s_bytes;
                        end
                        if (s_last)
                            state <= ST_LEN;
                    end
                end

                ST_LEN:  state <= ST_SUM;

                ST_SUM: begin
                    if (mul_v[MLAT] && mul_f[MLAT])
                        state <= ST_TAG;
                end

                ST_TAG: begin
                    if (o_kind == K_TAG) begin
                        tag       <= a_do;
                        tag_valid <= 1'b1;
                        state     <= ST_IDLE;

                        y_ctr <= 128'h0;
                        z_ctr <= 128'h0;
                        acc   <= 128'h0;
                    end
                end

                default: state <= ST_IDLE;
            endcase

            if (o_kind == K_DATA) begin
                m_valid <= 1'b1;
                m_data  <= o_xor;
                m_bytes <= o_bytes;
                m_last  <= o_last;
            end

            if (mul_v[MLAT] && state != ST_IDLE && state != ST_TAG)
                acc <= acc_next;
        end
    end
endmodule
