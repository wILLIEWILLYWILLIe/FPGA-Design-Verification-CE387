// =============================================================
// deemphasis.sv — 1st-order IIR De-emphasis Filter
// Matches C: iir() in fm_radio.cpp (taps=2, decimation=1)
//
// C logic per sample:
//   shift x: x[1]=x[0]; x[0]=x_in
//   shift y: y[1]=y[0]      <-- y[0] and y[1] both = old y[0]
//   y1 += DEQUANTIZE(x_coeffs[0]*x[0]) + DEQUANTIZE(x_coeffs[1]*x[1])
//   y2 += DEQUANTIZE(y_coeffs[0]*y[0]) + DEQUANTIZE(y_coeffs[1]*y[1])
//   y[0] = y1 + y2
//   output = y[taps-1] = y[1] = old y[0]
//
// x_coeffs = {178, 178}
// y_coeffs = {0, -666}    (QUANTIZE_F with W_PP=0.21140067)
// =============================================================

module deemphasis import fir_pkg::*; (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic signed [WIDTH-1:0]         x_in,
    output logic                            valid_out,
    output logic signed [WIDTH-1:0]         y_out
);

    // -------------------------------------------------------
    // Combinational: compute next y[0] from current state
    // -------------------------------------------------------
    logic signed [WIDTH-1:0] x0_reg;        // current x[0]
    logic signed [WIDTH-1:0] y0_reg;        // current y[0]

    logic signed [WIDTH-1:0] next_y0;
    logic signed [WIDTH-1:0] c_y1_comb, c_y2;
    logic signed [WIDTH-1:0] c_y1_reg; // Pipeline register
    logic signed [WIDTH-1:0] prod0, prod1, prod_y;
    logic signed [WIDTH-1:0] prod0_reg, prod1_reg; // Pipeline register for FIR products
    logic prod_valid;

    // FIR part 1 (Multiplications)
    always_comb begin
        prod0  = IIR_X_COEFFS[0] * x_in;
        prod1  = IIR_X_COEFFS[1] * x0_reg;
    end

    // FIR part 2 (Scaling and Addition)
    always_comb begin
        c_y1_comb = fir_pkg::div1024_f(prod0_reg) + fir_pkg::div1024_f(prod1_reg);
    end

    // IIR part (c_y2 and next_y0)
    always_comb begin
        // y_coeffs[0]=0 → skip; y_coeffs[1]=-666 * old y0
        prod_y = IIR_Y_COEFFS[1] * y0_reg;
        c_y2   = fir_pkg::div1024_f(prod_y);

        // Add registered FIR output with IIR feedback
        next_y0 = c_y1_reg + c_y2;
    end

    // -------------------------------------------------------
    // Sequential: update state and emit output
    // -------------------------------------------------------
    logic c_y1_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x0_reg    <= '0;
            y0_reg    <= '0;
            prod0_reg <= '0;
            prod1_reg <= '0;
            c_y1_reg  <= '0;
            y_out     <= '0;
            valid_out <= 1'b0;
            // pipeline valid
            prod_valid<= 1'b0;
            c_y1_valid<= 1'b0;
        end else begin
            valid_out <= 1'b0;
            c_y1_valid<= 1'b0;
            prod_valid<= 1'b0;
            
            if (valid_in) begin
                // Update FIR inputs and compute mult in comb
                x0_reg    <= x_in;
                prod0_reg <= prod0;
                prod1_reg <= prod1;
                prod_valid<= 1'b1;
            end
            
            if (prod_valid) begin
                // Update FIR part state and pipeline register
                c_y1_reg  <= c_y1_comb;
                c_y1_valid<= 1'b1;
            end
            
            if (c_y1_valid) begin
                // Output = old y[0] (before update)
                y_out     <= y0_reg;
                valid_out <= 1'b1;
                // Update IIR part state
                y0_reg    <= next_y0;
            end
        end
    end

endmodule
