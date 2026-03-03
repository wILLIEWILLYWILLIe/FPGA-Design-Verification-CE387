// =============================================================
// fir.sv — Parameterized Real FIR Filter with Decimation
// Matches C reference: fir() / fir_n() in fm_radio.cpp
//
// 2-stage pipelined MAC:
//   Stage A: compute products (DSP multiply + div1024_f) → register
//   Stage B: balanced binary adder tree → register output
// Throughput: 1 sample/clock.  Latency: +1 extra cycle.
// =============================================================

module fir import fir_pkg::*; #(
    parameter int TAPS      = 32,
    parameter int DECIM     = 1,
    parameter int WIDTH     = 32,
    parameter int CWIDTH    = 32,
    parameter int BITS      = 10
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic signed  [WIDTH-1:0]        x_in,
    input  logic signed  [CWIDTH-1:0]       coeffs [0:TAPS-1],
    output logic                            valid_out,
    output logic signed  [WIDTH-1:0]        y_out
);

    // Shift register: x[0] = newest, x[TAPS-1] = oldest
    logic signed [WIDTH-1:0] x_reg [0:TAPS-1];

    // Decimation counter (0 .. DECIM-1)
    logic [$clog2(TAPS > DECIM ? TAPS : DECIM)-1:0] cnt;

    // Output registers
    logic signed [WIDTH-1:0] y_reg;
    logic                    v_reg;

    // --------------------------------------------------------
    // Stage A: compute products (combinational)
    // --------------------------------------------------------
    localparam int PTAPS  = 2 ** $clog2(TAPS > 1 ? TAPS : 2);

    int prods [0:PTAPS-1];

    always_comb begin
        for (int k = 0; k < PTAPS; k++) begin
            if (k < TAPS) begin
                logic signed [WIDTH-1:0] x_val;
                int prod;
                x_val = (k == 0) ? x_in : x_reg[k-1];
                prod  = int'(coeffs[TAPS-1-k]) * int'(x_val);
                prods[k] = fir_pkg::div1024_f(prod);
            end else begin
                prods[k] = 0;
            end
        end
    end

    // Registered products (pipeline register between multiply and tree)
    int prod_reg [0:PTAPS-1];
    logic prod_valid;

    // --------------------------------------------------------
    // Stage B: balanced binary adder tree (from registered prods)
    // --------------------------------------------------------
    localparam int LEVELS = $clog2(PTAPS);

    int tree [0:LEVELS][0:PTAPS-1];
    int mac_result;

    always_comb begin
        // Level 0: registered products
        for (int k = 0; k < PTAPS; k++)
            tree[0][k] = prod_reg[k];

        // Binary tree reduction
        for (int lv = 0; lv < LEVELS; lv++) begin
            for (int k = 0; k < (PTAPS >> (lv+1)); k++)
                tree[lv+1][k] = tree[lv][2*k] + tree[lv][2*k+1];
            for (int k = (PTAPS >> (lv+1)); k < PTAPS; k++)
                tree[lv+1][k] = 0;
        end

        mac_result = tree[LEVELS][0];
    end

    // --------------------------------------------------------
    // Sequential
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < TAPS; k++) x_reg[k] <= '0;
            for (int k = 0; k < PTAPS; k++) prod_reg[k] <= '0;
            cnt        <= '0;
            prod_valid <= 1'b0;
            y_reg      <= '0;
            v_reg      <= 1'b0;
        end else begin
            prod_valid <= 1'b0;
            v_reg      <= 1'b0;

            if (valid_in) begin
                // Shift register
                for (int k = TAPS-1; k >= 1; k--)
                    x_reg[k] <= x_reg[k-1];
                x_reg[0] <= x_in;

                // Decimation: capture products when counter fires
                if (cnt == DECIM - 1) begin
                    cnt <= '0;
                    for (int k = 0; k < PTAPS; k++)
                        prod_reg[k] <= prods[k];
                    prod_valid <= 1'b1;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end

            // Stage B output: tree result → y_reg (1 cycle after prod_valid)
            if (prod_valid) begin
                y_reg <= WIDTH'(mac_result);
                v_reg <= 1'b1;
            end
        end
    end

    assign valid_out = v_reg;
    assign y_out     = y_reg;

endmodule
