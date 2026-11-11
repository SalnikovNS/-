`timescale 1ns/1ps

module tb_kuz_mgm;
    localparam [255:0] TEST_KEY =
        256'h8899aabbccddeeff0011223344556677fedcba98765432100123456789abcdef;

    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;

    reg          kstart = 0, kclear = 0;
    wire [1279:0] rk; wire kready, kbusy;
    kuz_keyexp u_key (.clk(clk), .rst(rst), .start(kstart), .clear(kclear),
                      .key(TEST_KEY), .rk(rk), .ready(kready), .busy(kbusy));

    reg          start = 0, decrypt = 0; reg [126:0] icn = 0; wire busy;
    reg          s_valid = 0; wire s_ready; reg [127:0] s_data = 0;
    reg  [4:0]   s_bytes = 0; reg s_aad = 0, s_last = 0;
    wire         m_valid, m_last, tag_valid; wire [127:0] m_data, tag; wire [4:0] m_bytes;

    kuz_mgm dut (.clk(clk), .rst(rst), .rk(rk),
        .start(start), .icn(icn), .decrypt(decrypt), .busy(busy),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data), .s_bytes(s_bytes),
        .s_aad(s_aad), .s_last(s_last),
        .m_valid(m_valid), .m_data(m_data), .m_bytes(m_bytes), .m_last(m_last),
        .tag_valid(tag_valid), .tag(tag));

    reg [143:0] mem [0:65535];
    reg [143:0] exp_q [0:255];
    integer p, q, c, errors, exp_n, exp_i, tag_seen, blocks, cycles;
    reg [127:0] exp_tag;
    integer gaps;

    always @(posedge clk) begin
        if (m_valid) begin
            if (exp_i >= exp_n) begin
                $display("case %0d: ERROR unexpected output block", c); errors = errors + 1;
            end else begin
                if (m_data !== exp_q[exp_i][127:0] || m_bytes !== exp_q[exp_i][132:128] ||
                    m_last !== exp_q[exp_i][134]) begin
                    $display("case %0d: ERROR block %0d: got %032x/%0d/%0d, expected %032x/%0d/%0d", c, exp_i,
                        m_data, m_bytes, m_last, exp_q[exp_i][127:0], exp_q[exp_i][132:128], exp_q[exp_i][134]);
                    errors = errors + 1;
                end
            end
            exp_i = exp_i + 1;
        end
        if (tag_valid) begin
            tag_seen = tag_seen + 1;
            if (tag !== exp_tag) begin
                $display("case %0d: ERROR tag %032x, expected %032x", c, tag, exp_tag); errors = errors + 1;
            end
        end
    end

    initial begin
        errors = 0; c = 0; p = 0; blocks = 0; cycles = 0; exp_n = 0; exp_i = 0; tag_seen = 0;
        gaps = $test$plusargs("gaps");
        $readmemh("sim/mgm_cases.hex", mem);
        repeat (5) @(negedge clk); rst = 0;
        @(negedge clk); kstart = 1; @(negedge clk); kstart = 0;
        wait (kready);
        if (rk[1279:1024] !== TEST_KEY) begin $display("ERROR: K1,K2"); errors = errors + 1; end

        if (rk[127:0] !== 128'h72e9dd7416bcf45b755dbaa88e4a4043) begin
            $display("ERROR: K10 = %032x", rk[127:0]); errors = errors + 1; end

        while (mem[p][143:136] != 8'd0) begin

            exp_n = 0; exp_i = 0; tag_seen = 0;
            q = p + 1;
            while (mem[q][143:136] == 8'd2) q = q + 1;
            while (mem[q][143:136] == 8'd3) begin exp_q[exp_n] = mem[q]; exp_n = exp_n + 1; q = q + 1; end
            exp_tag = mem[q][127:0];

            @(negedge clk); start = 1; icn = mem[p][126:0]; decrypt = mem[p][128];
            @(negedge clk); start = 0; p = p + 1;

            while (mem[p][143:136] == 8'd2) begin
                @(negedge clk);
                if (gaps && ($urandom % 3) == 0) s_valid = 0;
                else begin
                    s_valid = 1; s_data = mem[p][127:0]; s_bytes = mem[p][132:128];
                    s_aad = mem[p][133]; s_last = mem[p][134];
                    @(posedge clk); if (s_ready) begin p = p + 1; blocks = blocks + 1; end
                end
            end
            @(negedge clk); s_valid = 0; s_last = 0;
            p = q + 2;
            wait (!busy); @(posedge clk); @(negedge clk);
            if (exp_i != exp_n) begin $display("case %0d: ERROR %0d of %0d blocks", c, exp_i, exp_n); errors = errors + 1; end
            if (tag_seen != 1) begin $display("case %0d: ERROR tag_valid count %0d", c, tag_seen); errors = errors + 1; end
            c = c + 1;
        end

        @(negedge clk); kclear = 1; @(negedge clk); kclear = 0; @(negedge clk);
        if (kready !== 0 || rk !== 1280'h0) begin $display("ERROR: round keys not wiped"); errors = errors + 1; end

        if (errors == 0) $display("==== ALL %0d MGM CASES PASSED (%0d blocks) ====", c, blocks);
        else             $display("==== FAILED: %0d error(s) ====", errors);
        $finish;
    end
    always @(posedge clk) cycles = cycles + 1;
    initial begin #50_000_000; $display("==== FAILED: timeout ===="); $finish; end
endmodule
