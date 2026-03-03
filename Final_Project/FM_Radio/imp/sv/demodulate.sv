// =============================================================
// demodulate.sv — FM Demodulator with pipelined divider
//
// Pipeline:
//   Stg1:   I/Q cross-multiply → r_val, i_val          (1 cycle)
//   Stg2a:  abs, numerator, denominator preparation     (1 cycle)
//   Stg2b:  32-stage pipelined restoring divider        (32 cycles latency,
//           1 sample/clock THROUGHPUT)
//   Stg3:   finish qarctan & output gain                (1 cycle)
//   Total latency: 35 cycles, throughput: 1 sample/clock
// =============================================================

module demodulate import fir_pkg::*, qarctan_pkg::*; (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic signed [WIDTH-1:0]         real_in,
    input  logic signed [WIDTH-1:0]         imag_in,
    output logic                            valid_out,
    output logic signed [WIDTH-1:0]         demod_out
);

    // Previous I/Q sample
    logic signed [WIDTH-1:0] real_prev, imag_prev;

    // ----------------------------------------------------
    // PIPELINE STAGE 1a: I/Q Cross-Multiply
    // ----------------------------------------------------
    int prod_rr, prod_ii, prod_ri, prod_ir;

    always_comb begin
        prod_rr = int'(real_prev) * int'(real_in);
        prod_ii = (-int'(imag_prev)) * int'(imag_in);
        prod_ri = int'(real_prev) * int'(imag_in);
        prod_ir = (-int'(imag_prev)) * int'(real_in);
    end

    int stg1a_prod_rr, stg1a_prod_ii, stg1a_prod_ri, stg1a_prod_ir;
    logic stg1a_valid;

    // ----------------------------------------------------
    // PIPELINE STAGE 1b: div1024_f & sum/diff -> r_val, i_val
    // ----------------------------------------------------
    int r_val, i_val;

    int stg1_r_val, stg1_i_val;
    logic stg1_valid;

    always_comb begin
        r_val = fir_pkg::div1024_f(stg1a_prod_rr) - fir_pkg::div1024_f(stg1a_prod_ii);
        i_val = fir_pkg::div1024_f(stg1a_prod_ri) + fir_pkg::div1024_f(stg1a_prod_ir);
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 2a: Prepare numerator & denominator
    // ----------------------------------------------------
    int stg2a_abs_y;
    int stg2a_numer_calc, stg2a_denom_calc;

    int stg2a_numer, stg2a_denom;
    logic stg2a_x_ge0, stg2a_y_neg;
    logic stg2a_valid;

    always_comb begin
        stg2a_abs_y = (stg1_i_val < 0) ? -stg1_i_val : stg1_i_val;
        stg2a_abs_y = stg2a_abs_y + 1;

        if (stg1_r_val >= 0) begin
            stg2a_numer_calc = (stg1_r_val - stg2a_abs_y) * QUANT_VAL;
            stg2a_denom_calc = stg1_r_val + stg2a_abs_y;
        end else begin
            stg2a_numer_calc = (stg1_r_val + stg2a_abs_y) * QUANT_VAL;
            stg2a_denom_calc = stg2a_abs_y - stg1_r_val;
        end
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 2b: 32-stage pipelined restoring divider
    //   Each stage computes 1 bit of the quotient.
    //   Throughput: 1 sample/clock.  Latency: 32 cycles.
    // ----------------------------------------------------

    // Pipeline arrays: index [0] = input, [32] = output
    logic [32:0] p_rem   [0:32];  // remainder (33-bit for comparison)
    logic [31:0] p_quo   [0:32];  // quotient being built
    logic [31:0] p_num   [0:32];  // shifted numerator (MSB used each stage)
    logic [31:0] p_den   [0:32];  // denominator (passed through)
    logic        p_neg   [0:32];  // negate result flag
    logic        p_xge   [0:32];  // x >= 0 flag for qarctan
    logic        p_yneg  [0:32];  // y < 0 flag for qarctan
    logic        p_valid [0:32];  // valid token

    // Stage 0 inputs: take abs values from stg2a registers
    always_comb begin
        p_rem[0]   = '0;
        p_quo[0]   = '0;
        p_num[0]   = (stg2a_numer < 0) ? 32'(-(stg2a_numer)) : 32'(stg2a_numer);
        p_den[0]   = (stg2a_denom < 0) ? 32'(-(stg2a_denom)) : 32'(stg2a_denom);
        p_neg[0]   = stg2a_numer[31] ^ stg2a_denom[31];
        p_xge[0]   = stg2a_x_ge0;
        p_yneg[0]  = stg2a_y_neg;
        p_valid[0] = stg2a_valid;
    end

    // Generate 32 pipeline stages (one bit per stage)
    genvar g;
    generate
        for (g = 0; g < 32; g++) begin : div_pipe
            // Trial subtraction: shift remainder left, bring in MSB of numerator
            logic [32:0] trial;
            assign trial = {p_rem[g][31:0], p_num[g][31]};

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    p_rem[g+1]   <= '0;
                    p_quo[g+1]   <= '0;
                    p_num[g+1]   <= '0;
                    p_den[g+1]   <= '0;
                    p_neg[g+1]   <= 1'b0;
                    p_xge[g+1]   <= 1'b0;
                    p_yneg[g+1]  <= 1'b0;
                    p_valid[g+1] <= 1'b0;
                end else begin
                    // Restoring division: one bit per stage
                    if (trial >= {1'b0, p_den[g]}) begin
                        p_rem[g+1] <= trial - {1'b0, p_den[g]};
                        p_quo[g+1] <= {p_quo[g][30:0], 1'b1};
                    end else begin
                        p_rem[g+1] <= trial;
                        p_quo[g+1] <= {p_quo[g][30:0], 1'b0};
                    end
                    p_num[g+1]   <= {p_num[g][30:0], 1'b0};  // shift left
                    p_den[g+1]   <= p_den[g];
                    p_neg[g+1]   <= p_neg[g];
                    p_xge[g+1]   <= p_xge[g];
                    p_yneg[g+1]  <= p_yneg[g];
                    p_valid[g+1] <= p_valid[g];
                end
            end
        end
    endgenerate

    // Divider output: apply sign correction (combinational)
    int  stg2b_r;
    logic stg2b_x_ge0, stg2b_y_neg, stg2b_valid;

    always_comb begin
        stg2b_r     = p_neg[32] ? -int'(p_quo[32]) : int'(p_quo[32]);
        stg2b_x_ge0 = p_xge[32];
        stg2b_y_neg = p_yneg[32];
        stg2b_valid = p_valid[32];
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 2c: Register Divider Output
    // ----------------------------------------------------
    int   stg2c_r;
    logic stg2c_x_ge0, stg2c_y_neg, stg2c_valid;

    // (Registers for 2c are instantiated in the always_ff block below)

    // ----------------------------------------------------
    // PIPELINE STAGE 3a: QUAD multiply + angle calculation
    // ----------------------------------------------------
    int stg3a_prod, stg3a_angle_calc;

    always_comb begin
        stg3a_prod = qarctan_pkg::QUAD1 * stg2c_r;
        if (stg2c_x_ge0)
            stg3a_angle_calc = qarctan_pkg::QUAD1 - fir_pkg::div1024_f(stg3a_prod);
        else
            stg3a_angle_calc = qarctan_pkg::QUAD3 - fir_pkg::div1024_f(stg3a_prod);
    end

    // Stage 3a registers
    int   stg3a_angle;
    logic stg3a_y_neg;
    logic stg3a_valid;

    // ----------------------------------------------------
    // PIPELINE STAGE 3b: y_neg negate -> Register
    // ----------------------------------------------------
    int stg3b_angle_signed;

    always_comb begin
        stg3b_angle_signed = stg3a_y_neg ? -stg3a_angle : stg3a_angle;
    end

    int stg3b_angle_signed_reg;
    logic stg3b_valid;

    // ----------------------------------------------------
    // PIPELINE STAGE 3c: gain multiply
    // ----------------------------------------------------
    int stg3c_prod_calc;

    always_comb begin
        stg3c_prod_calc = FM_DEMOD_GAIN * stg3b_angle_signed_reg;
    end

    int stg3c_prod_reg;
    logic stg3c_valid;

    // ----------------------------------------------------
    // PIPELINE STAGE 3d: shift -> Output
    // ----------------------------------------------------
    int stg3d_demod_calc;

    always_comb begin
        stg3d_demod_calc = fir_pkg::div1024_f(stg3c_prod_reg);
    end

    // ----------------------------------------------------
    // Sequential: Stages 1, 2a, 3a, 3b (divider is in generate)
    // ----------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            real_prev    <= '0;
            imag_prev    <= '0;
            stg1a_prod_rr <= '0;
            stg1a_prod_ii <= '0;
            stg1a_prod_ri <= '0;
            stg1a_prod_ir <= '0;
            stg1a_valid   <= 1'b0;
            stg1_r_val   <= '0;
            stg1_i_val   <= '0;
            stg1_valid   <= 1'b0;
            stg2a_numer  <= '0;
            stg2a_denom  <= 32'd1;
            stg2a_x_ge0  <= 1'b0;
            stg2a_y_neg  <= 1'b0;
            stg2a_valid  <= 1'b0;
            stg2c_r      <= '0;
            stg2c_x_ge0  <= 1'b0;
            stg2c_y_neg  <= 1'b0;
            stg2c_valid  <= 1'b0;
            stg3a_angle  <= '0;
            stg3a_y_neg  <= 1'b0;
            stg3a_valid  <= 1'b0;
            stg3b_angle_signed_reg <= '0;
            stg3b_valid  <= 1'b0;
            stg3c_prod_reg <= '0;
            stg3c_valid  <= 1'b0;
            demod_out    <= '0;
            valid_out    <= 1'b0;
        end else begin
            // Input capture for NEXT cycle's cross-multiply
            if (valid_in) begin
                real_prev  <= real_in;
                imag_prev  <= imag_in;
            end

            // Stage 1a (multiply registered inputs)
            stg1a_valid <= valid_in;
            if (valid_in) begin
                stg1a_prod_rr <= prod_rr;
                stg1a_prod_ii <= prod_ii;
                stg1a_prod_ri <= prod_ri;
                stg1a_prod_ir <= prod_ir;
            end

            // Stage 1b (scale and add/sub)
            stg1_valid <= stg1a_valid;
            if (stg1a_valid) begin
                stg1_r_val <= r_val;
                stg1_i_val <= i_val;
            end

            // Stage 2a
            stg2a_valid <= stg1_valid;
            if (stg1_valid) begin
                stg2a_numer <= stg2a_numer_calc;
                stg2a_denom <= stg2a_denom_calc;
                stg2a_x_ge0 <= (stg1_r_val >= 0);
                stg2a_y_neg <= (stg1_i_val < 0);
            end

            // Stage 2c (after divider)
            stg2c_valid <= stg2b_valid;
            if (stg2b_valid) begin
                stg2c_r     <= stg2b_r;
                stg2c_x_ge0 <= stg2b_x_ge0;
                stg2c_y_neg <= stg2b_y_neg;
            end

            // Stage 3a
            stg3a_valid <= stg2c_valid;
            if (stg2c_valid) begin
                stg3a_angle <= stg3a_angle_calc;
                stg3a_y_neg <= stg2c_y_neg;
            end

            // Stage 3b
            stg3b_valid <= stg3a_valid;
            if (stg3a_valid) begin
                stg3b_angle_signed_reg <= stg3b_angle_signed;
            end

            // Stage 3c
            stg3c_valid <= stg3b_valid;
            if (stg3b_valid) begin
                stg3c_prod_reg <= stg3c_prod_calc;
            end

            // Stage 3d -> output
            valid_out <= stg3c_valid;
            if (stg3c_valid) begin
                demod_out <= stg3d_demod_calc;
            end
        end
    end

endmodule
