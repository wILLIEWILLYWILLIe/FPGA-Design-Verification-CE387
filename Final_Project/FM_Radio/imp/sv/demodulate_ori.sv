// =============================================================
// demodulate.sv — FM Demodulator
// Matches C reference: demodulate() in fm_radio.cpp
// Uses qarctan_f() function for inline evaluation
//
// 4-stage pipeline:
//   Stg1:  I/Q cross-multiply → r_val, i_val
//   Stg2a: abs, numerator, denominator preparation
//   Stg2b: division (numer / denom → r)
//   Stg3:  finish qarctan & output gain
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
    // PIPELINE STAGE 1: I/Q Cross-Multiply -> sum/diff
    // ----------------------------------------------------
    int prod_rr, prod_ii, prod_ri, prod_ir;
    int r_val, i_val;

    // Stage 1 Registers
    int stg1_r_val, stg1_i_val;
    logic stg1_valid;

    always_comb begin
        prod_rr = int'(real_prev) * int'(real_in);
        prod_ii = (-int'(imag_prev)) * int'(imag_in);
        prod_ri = int'(real_prev) * int'(imag_in);
        prod_ir = (-int'(imag_prev)) * int'(real_in);

        r_val = fir_pkg::div1024_f(prod_rr) - fir_pkg::div1024_f(prod_ii);
        i_val = fir_pkg::div1024_f(prod_ri) + fir_pkg::div1024_f(prod_ir);
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 2a: Prepare numerator & denominator
    // ----------------------------------------------------
    int stg2a_abs_y;
    int stg2a_numer_calc, stg2a_denom_calc;

    // Stage 2a Registers
    int stg2a_numer, stg2a_denom;
    logic stg2a_x_ge0, stg2a_y_neg;
    logic stg2a_valid;

    always_comb begin
        // abs(y) + 1
        stg2a_abs_y = (stg1_i_val < 0) ? -stg1_i_val : stg1_i_val;
        stg2a_abs_y = stg2a_abs_y + 1;

        // Prepare numerator and denominator for division
        if (stg1_r_val >= 0) begin
            stg2a_numer_calc = (stg1_r_val - stg2a_abs_y) * QUANT_VAL;
            stg2a_denom_calc = stg1_r_val + stg2a_abs_y;
        end else begin
            stg2a_numer_calc = (stg1_r_val + stg2a_abs_y) * QUANT_VAL;
            stg2a_denom_calc = stg2a_abs_y - stg1_r_val;
        end
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 2b: Division only
    // ----------------------------------------------------
    int stg2b_r_calc;

    // Stage 2b Registers
    int stg2b_r;
    logic stg2b_x_ge0, stg2b_y_neg;
    logic stg2b_valid;

    always_comb begin
        stg2b_r_calc = stg2a_numer / stg2a_denom;
    end

    // ----------------------------------------------------
    // PIPELINE STAGE 3: Finish qarctan & Output Gain
    // ----------------------------------------------------
    int stg3_prod, stg3_angle;
    int demod_val;

    always_comb begin
        if (stg2b_x_ge0) begin
            stg3_prod = qarctan_pkg::QUAD1 * stg2b_r;
            stg3_angle = qarctan_pkg::QUAD1 - fir_pkg::div1024_f(stg3_prod);
        end else begin
            stg3_prod = qarctan_pkg::QUAD1 * stg2b_r;
            stg3_angle = qarctan_pkg::QUAD3 - fir_pkg::div1024_f(stg3_prod);
        end

        // negate if in quad III or IV
        stg3_angle = stg2b_y_neg ? -stg3_angle : stg3_angle;

        // out = DEQUANTIZE(gain * qarctan(i, r))
        demod_val = fir_pkg::div1024_f(FM_DEMOD_GAIN * stg3_angle);
    end

    // ----------------------------------------------------
    // Pipeline Sequential Control
    // ----------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            real_prev   <= '0;
            imag_prev   <= '0;

            stg1_r_val  <= '0;
            stg1_i_val  <= '0;
            stg1_valid  <= 1'b0;

            stg2a_numer <= '0;
            stg2a_denom <= 32'd1;  // avoid div-by-zero during reset
            stg2a_x_ge0 <= 1'b0;
            stg2a_y_neg <= 1'b0;
            stg2a_valid <= 1'b0;

            stg2b_r     <= '0;
            stg2b_x_ge0 <= 1'b0;
            stg2b_y_neg <= 1'b0;
            stg2b_valid <= 1'b0;

            demod_out   <= '0;
            valid_out   <= 1'b0;
        end else begin
            // Stage 1
            stg1_valid <= valid_in;
            if (valid_in) begin
                stg1_r_val <= r_val;
                stg1_i_val <= i_val;
                real_prev  <= real_in;
                imag_prev  <= imag_in;
            end

            // Stage 2a
            stg2a_valid <= stg1_valid;
            if (stg1_valid) begin
                stg2a_numer <= stg2a_numer_calc;
                stg2a_denom <= stg2a_denom_calc;
                stg2a_x_ge0 <= (stg1_r_val >= 0);
                stg2a_y_neg <= (stg1_i_val < 0);
            end

            // Stage 2b
            stg2b_valid <= stg2a_valid;
            if (stg2a_valid) begin
                stg2b_r     <= stg2b_r_calc;
                stg2b_x_ge0 <= stg2a_x_ge0;
                stg2b_y_neg <= stg2a_y_neg;
            end

            // Stage 3 (Output)
            valid_out <= stg2b_valid;
            if (stg2b_valid) begin
                demod_out <= demod_val;
            end
        end
    end

endmodule
