// =============================================================
// fm_radio_top.sv — Full FM Radio Stereo DSP Pipeline
// Input:  I/Q samples @ 256 kHz (Q10 format)
// Output: left/right audio @ 32 kHz (16-bit range)
//
// Pipeline (two-process modules throughout):
//   fir(CH_I) ─┐
//              ├─► demodulate ─► fir(LPR,×8) ─[4-cy delay]─► add_sub(+) ─► deemph ─► gain ─► left
//   fir(CH_Q) ─┘       │                                    └► add_sub(-) ─► deemph ─► gain ─► right
//                       ├─► fir(BP_PILOT) ─► ×² ─► fir(HP) ─►─────────────────┐
//                       └─► fir(BP_LMR) ─────────────────────► × ─► fir(LMR,×8)─┘
// =============================================================

module fm_radio_top import fir_pkg::*, qarctan_pkg::*; (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            valid_in,
    input  logic signed [WIDTH-1:0]         I_in,
    input  logic signed [WIDTH-1:0]         Q_in,
    output logic                            valid_out,
    output logic signed [WIDTH-1:0]         left_out,
    output logic signed [WIDTH-1:0]         right_out
);

    // -------------------------------------------------------
    // Coefficient wires for each FIR instance
    // -------------------------------------------------------
    logic signed [CWIDTH-1:0] ch_coeffs    [0:CHANNEL_TAPS-1];
    logic signed [CWIDTH-1:0] lpr_coeffs   [0:AUDIO_LPR_TAPS-1];
    logic signed [CWIDTH-1:0] pilot_coeffs [0:BP_PILOT_TAPS-1];
    logic signed [CWIDTH-1:0] hp_coeffs    [0:HP_TAPS-1];
    logic signed [CWIDTH-1:0] lmr_coeffs   [0:AUDIO_LMR_TAPS-1];
    logic signed [CWIDTH-1:0] bplmr_coeffs [0:BP_LMR_TAPS-1];

    genvar gi;
    generate
        for (gi = 0; gi < CHANNEL_TAPS;    gi++) assign ch_coeffs[gi]    = CHANNEL_COEFFS[gi];
        for (gi = 0; gi < AUDIO_LPR_TAPS;  gi++) assign lpr_coeffs[gi]   = AUDIO_LPR_COEFFS[gi];
        for (gi = 0; gi < BP_PILOT_TAPS;   gi++) assign pilot_coeffs[gi] = BP_PILOT_COEFFS[gi];
        for (gi = 0; gi < HP_TAPS;         gi++) assign hp_coeffs[gi]    = HP_COEFFS[gi];
        for (gi = 0; gi < AUDIO_LMR_TAPS;  gi++) assign lmr_coeffs[gi]   = AUDIO_LMR_COEFFS[gi];
        for (gi = 0; gi < BP_LMR_TAPS;     gi++) assign bplmr_coeffs[gi] = BP_LMR_COEFFS[gi];
    endgenerate

    // -------------------------------------------------------
    // Stage 1: Channel Filter (I and Q)
    // -------------------------------------------------------
    logic                    ch_I_valid, ch_Q_valid;
    logic signed [WIDTH-1:0] ch_I, ch_Q;

    fir #(.TAPS(CHANNEL_TAPS),.DECIM(1),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_ch_I (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.x_in(I_in),
        .coeffs(ch_coeffs),.valid_out(ch_I_valid),.y_out(ch_I));

    fir #(.TAPS(CHANNEL_TAPS),.DECIM(1),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_ch_Q (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),.x_in(Q_in),
        .coeffs(ch_coeffs),.valid_out(ch_Q_valid),.y_out(ch_Q));

    // -------------------------------------------------------
    // Stage 2: FM Demodulator (uses ch_I_valid as trigger)
    // -------------------------------------------------------
    logic                    demod_valid;
    logic signed [WIDTH-1:0] demod;

    demodulate u_demod (
        .clk(clk),.rst_n(rst_n),.valid_in(ch_I_valid),
        .real_in(ch_I),.imag_in(ch_Q),
        .valid_out(demod_valid),.demod_out(demod));

    // -------------------------------------------------------
    // Stage 3a: L+R path — decimating LPF (decim=8)
    // -------------------------------------------------------
    logic                    lpr_valid;
    logic signed [WIDTH-1:0] audio_lpr;

    fir #(.TAPS(AUDIO_LPR_TAPS),.DECIM(AUDIO_DECIM),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_lpr (
        .clk(clk),.rst_n(rst_n),.valid_in(demod_valid),.x_in(demod),
        .coeffs(lpr_coeffs),.valid_out(lpr_valid),.y_out(audio_lpr));

    // -------------------------------------------------------
    // Stage 3b: Pilot path — BP Filter → Square → HP Filter
    // -------------------------------------------------------
    logic                    bppilot_valid;
    logic signed [WIDTH-1:0] bp_pilot;

    fir #(.TAPS(BP_PILOT_TAPS),.DECIM(1),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_bppilot (
        .clk(clk),.rst_n(rst_n),.valid_in(demod_valid),.x_in(demod),
        .coeffs(pilot_coeffs),.valid_out(bppilot_valid),.y_out(bp_pilot));

    logic                    pilotq_valid;
    logic signed [WIDTH-1:0] pilot_sq;

    multiply u_multiply_sq (
        .clk(clk),.rst_n(rst_n),.valid_in(bppilot_valid),
        .x_in(bp_pilot),.y_in(bp_pilot),.valid_out(pilotq_valid),.out(pilot_sq));

    logic                    hp_valid;
    logic signed [WIDTH-1:0] pilot_38k;

    fir #(.TAPS(HP_TAPS),.DECIM(1),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_hp (
        .clk(clk),.rst_n(rst_n),.valid_in(pilotq_valid),.x_in(pilot_sq),
        .coeffs(hp_coeffs),.valid_out(hp_valid),.y_out(pilot_38k));

    // -------------------------------------------------------
    // Stage 3c: L-R path — BP Filter + 3-cycle delay
    // -------------------------------------------------------
    // bp_lmr needs to wait for pilot_38k.
    // pilot_38k path: multiply_sq(1) + fir_hp(2 with pipeline) = 3 cycles
    // So we delay bp_lmr by 3 cycles.
    logic                    bplmr_valid;
    logic signed [WIDTH-1:0] bp_lmr;

    fir #(.TAPS(BP_LMR_TAPS),.DECIM(1),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_bplmr (
        .clk(clk),.rst_n(rst_n),.valid_in(demod_valid),.x_in(demod),
        .coeffs(bplmr_coeffs),.valid_out(bplmr_valid),.y_out(bp_lmr));

    logic signed [WIDTH-1:0] bp_lmr_d1, bp_lmr_d2, bp_lmr_d3;
    logic                    bplmr_v_d1, bplmr_v_d2, bplmr_v_d3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bp_lmr_d1 <= '0; bp_lmr_d2 <= '0; bp_lmr_d3 <= '0;
            bplmr_v_d1 <= 1'b0; bplmr_v_d2 <= 1'b0; bplmr_v_d3 <= 1'b0;
        end else begin
            bp_lmr_d1 <= bp_lmr;
            bplmr_v_d1 <= bplmr_valid;
            bp_lmr_d2 <= bp_lmr_d1;
            bplmr_v_d2 <= bplmr_v_d1;
            bp_lmr_d3 <= bp_lmr_d2;
            bplmr_v_d3 <= bplmr_v_d2;
        end
    end

    // -------------------------------------------------------
    // Stage 4: L-R Demod (pilot_38k × bp_lmr_delay) → LMR LPF
    // -------------------------------------------------------
    logic                    lmr_bb_valid;
    logic signed [WIDTH-1:0] lmr_bb;

    // Use hp_valid (or bplmr_v_d3, they arrive at the same time)
    multiply u_multiply_lmr (
        .clk(clk),.rst_n(rst_n),.valid_in(hp_valid),
        .x_in(pilot_38k),.y_in(bp_lmr_d3),.valid_out(lmr_bb_valid),.out(lmr_bb));

    logic                    lmr_valid;
    logic signed [WIDTH-1:0] audio_lmr;

    fir #(.TAPS(AUDIO_LMR_TAPS),.DECIM(AUDIO_DECIM),.WIDTH(WIDTH),.CWIDTH(CWIDTH),.BITS(BITS)) u_fir_lmr (
        .clk(clk),.rst_n(rst_n),.valid_in(lmr_bb_valid),.x_in(lmr_bb),
        .coeffs(lmr_coeffs),.valid_out(lmr_valid),.y_out(audio_lmr));

    // -------------------------------------------------------
    // Stage 5: Timing alignment
    // LMR path has 6 extra decim=1 stages before decimating FIR:
    //   fir_bppilot(2) + multiply_sq(1) + fir_hp(2) + multiply_lmr(1) = 6 cycles
    //   (each pipelined FIR now takes 2 cycles instead of 1)
    // audio_lpr fires 6 cycles before audio_lmr → delay lpr 6 cycles.
    // -------------------------------------------------------
    localparam int LPR_DELAY = 6;

    logic signed [WIDTH-1:0] lpr_delay_d [0:LPR_DELAY-1];
    logic                    lpr_delay_v [0:LPR_DELAY-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LPR_DELAY; i++) begin
                lpr_delay_d[i] <= '0;
                lpr_delay_v[i] <= 1'b0;
            end
        end else begin
            lpr_delay_d[0] <= audio_lpr;
            lpr_delay_v[0] <= lpr_valid;
            for (int i = 1; i < LPR_DELAY; i++) begin
                lpr_delay_d[i] <= lpr_delay_d[i-1];
                lpr_delay_v[i] <= lpr_delay_v[i-1];
            end
        end
    end

    logic signed [WIDTH-1:0] audio_lpr_aligned;
    logic                    lpr_aligned_valid;
    assign audio_lpr_aligned = lpr_delay_d[LPR_DELAY-1];
    assign lpr_aligned_valid  = lpr_delay_v[LPR_DELAY-1];

    // -------------------------------------------------------
    // Stage 6: Add/Sub → left_raw and right_raw
    // -------------------------------------------------------
    logic                    left_raw_valid,  right_raw_valid;
    logic signed [WIDTH-1:0] left_raw,         right_raw;

    add_sub u_add (
        .clk(clk),.rst_n(rst_n),.valid_in(lpr_aligned_valid),.do_sub(1'b0),
        .x_in(audio_lpr_aligned),.y_in(audio_lmr),
        .valid_out(left_raw_valid),.z_out(left_raw));

    add_sub u_sub (
        .clk(clk),.rst_n(rst_n),.valid_in(lpr_aligned_valid),.do_sub(1'b1),
        .x_in(audio_lpr_aligned),.y_in(audio_lmr),
        .valid_out(right_raw_valid),.z_out(right_raw));

    // -------------------------------------------------------
    // Stage 6.5: Pipeline Register between Add/Sub and De-emphasis
    // -------------------------------------------------------
    logic                    left_raw_reg_valid, right_raw_reg_valid;
    logic signed [WIDTH-1:0] left_raw_reg,       right_raw_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_raw_reg_valid  <= 1'b0;
            right_raw_reg_valid <= 1'b0;
            left_raw_reg        <= '0;
            right_raw_reg       <= '0;
        end else begin
            left_raw_reg_valid  <= left_raw_valid;
            right_raw_reg_valid <= right_raw_valid;
            if (left_raw_valid)  left_raw_reg  <= left_raw;
            if (right_raw_valid) right_raw_reg <= right_raw;
        end
    end

    // -------------------------------------------------------
    // Stage 7: De-emphasis (Left and Right)
    // -------------------------------------------------------
    logic                    left_deemph_valid,  right_deemph_valid;
    logic signed [WIDTH-1:0] left_deemph,         right_deemph;

    deemphasis u_deemph_L (
        .clk(clk),.rst_n(rst_n),.valid_in(left_raw_reg_valid),
        .x_in(left_raw_reg),.valid_out(left_deemph_valid),.y_out(left_deemph));

    deemphasis u_deemph_R (
        .clk(clk),.rst_n(rst_n),.valid_in(right_raw_reg_valid),
        .x_in(right_raw_reg),.valid_out(right_deemph_valid),.y_out(right_deemph));

    // -------------------------------------------------------
    // Stage 8: Gain / Volume Control (Left and Right)
    // -------------------------------------------------------
    logic                    left_gain_valid, right_gain_valid;

    gain u_gain_L (
        .clk(clk),.rst_n(rst_n),.valid_in(left_deemph_valid),
        .x_in(left_deemph),.gain_val(WIDTH'(VOLUME_LEVEL)),
        .valid_out(left_gain_valid),.y_out(left_out));

    gain u_gain_R (
        .clk(clk),.rst_n(rst_n),.valid_in(right_deemph_valid),
        .x_in(right_deemph),.gain_val(WIDTH'(VOLUME_LEVEL)),
        .valid_out(right_gain_valid),.y_out(right_out));

    assign valid_out = left_gain_valid;

endmodule
