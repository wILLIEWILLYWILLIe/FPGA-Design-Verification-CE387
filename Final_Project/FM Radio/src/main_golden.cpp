
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "fm_radio.h"

// -------------------------------------------------------
// Golden reference generator
// Runs the full FM radio pipeline and dumps all
// intermediate signals to test/ for FPGA verification.
// -------------------------------------------------------

#define DUMP_INT(fname, arr, n) dump_int(fname, arr, n)

static void dump_int(const char *path, int *arr, int n)
{
    FILE *f = fopen(path, "w");
    if (!f) { printf("ERROR: cannot open %s\n", path); return; }
    for (int i = 0; i < n; i++)
        fprintf(f, "%d\n", arr[i]);
    fclose(f);
    printf("  [dump] %s (%d samples)\n", path, n);
}

void fm_radio_golden(unsigned char *IQ,
                     int *left_audio, int *right_audio,
                     const char *out_dir)
{
    char path[256];

    // ---------- internal buffers ----------
    static int I[SAMPLES],   Q[SAMPLES];
    static int I_fir[SAMPLES], Q_fir[SAMPLES];
    static int demod[SAMPLES];
    static int bp_pilot_filter[SAMPLES];
    static int bp_lmr_filter[SAMPLES];
    static int hp_pilot_filter[SAMPLES];
    static int audio_lpr_filter[AUDIO_SAMPLES];
    static int audio_lmr_filter[AUDIO_SAMPLES];
    static int square[SAMPLES];
    static int multiply[SAMPLES];
    static int left[AUDIO_SAMPLES],  right[AUDIO_SAMPLES];
    static int left_deemph[AUDIO_SAMPLES], right_deemph[AUDIO_SAMPLES];

    static int fir_cmplx_x_real[MAX_TAPS], fir_cmplx_x_imag[MAX_TAPS];
    static int demod_real[] = {0},   demod_imag[] = {0};
    static int fir_lpr_x[MAX_TAPS],  fir_lmr_x[MAX_TAPS];
    static int fir_bp_x[MAX_TAPS],   fir_pilot_x[MAX_TAPS];
    static int fir_hp_x[MAX_TAPS];
    static int deemph_l_x[MAX_TAPS], deemph_l_y[MAX_TAPS];
    static int deemph_r_x[MAX_TAPS], deemph_r_y[MAX_TAPS];

    // ---------- pipeline ----------
    read_IQ(IQ, I, Q, SAMPLES);
    snprintf(path, sizeof(path), "%s/in_I.txt",         out_dir); DUMP_INT(path, I, SAMPLES);
    snprintf(path, sizeof(path), "%s/in_Q.txt",         out_dir); DUMP_INT(path, Q, SAMPLES);

    fir_cmplx_n(I, Q, SAMPLES, CHANNEL_COEFFS_REAL, CHANNEL_COEFFS_IMAG,
                fir_cmplx_x_real, fir_cmplx_x_imag,
                CHANNEL_COEFF_TAPS, 1, I_fir, Q_fir);
    snprintf(path, sizeof(path), "%s/ch_I.txt",         out_dir); DUMP_INT(path, I_fir, SAMPLES);
    snprintf(path, sizeof(path), "%s/ch_Q.txt",         out_dir); DUMP_INT(path, Q_fir, SAMPLES);

    demodulate_n(I_fir, Q_fir, demod_real, demod_imag, SAMPLES, FM_DEMOD_GAIN, demod);
    snprintf(path, sizeof(path), "%s/demod.txt",        out_dir); DUMP_INT(path, demod, SAMPLES);

    // L+R path
    fir_n(demod, SAMPLES, AUDIO_LPR_COEFFS, fir_lpr_x,
          AUDIO_LPR_COEFF_TAPS, AUDIO_DECIM, audio_lpr_filter);
    snprintf(path, sizeof(path), "%s/audio_lpr.txt",    out_dir); DUMP_INT(path, audio_lpr_filter, AUDIO_SAMPLES);

    // L-R bandpass
    fir_n(demod, SAMPLES, BP_LMR_COEFFS, fir_bp_x,
          BP_LMR_COEFF_TAPS, 1, bp_lmr_filter);
    snprintf(path, sizeof(path), "%s/bp_lmr.txt",       out_dir); DUMP_INT(path, bp_lmr_filter, SAMPLES);

    // Pilot bandpass
    fir_n(demod, SAMPLES, BP_PILOT_COEFFS, fir_pilot_x,
          BP_PILOT_COEFF_TAPS, 1, bp_pilot_filter);
    snprintf(path, sizeof(path), "%s/bp_pilot.txt",     out_dir); DUMP_INT(path, bp_pilot_filter, SAMPLES);

    // Square pilot → 38 kHz + DC
    multiply_n(bp_pilot_filter, bp_pilot_filter, SAMPLES, square);
    snprintf(path, sizeof(path), "%s/pilot_sq.txt",     out_dir); DUMP_INT(path, square, SAMPLES);

    // HP filter → remove DC
    fir_n(square, SAMPLES, HP_COEFFS, fir_hp_x,
          HP_COEFF_TAPS, 1, hp_pilot_filter);
    snprintf(path, sizeof(path), "%s/pilot_38k.txt",    out_dir); DUMP_INT(path, hp_pilot_filter, SAMPLES);

    // Demodulate L-R
    multiply_n(hp_pilot_filter, bp_lmr_filter, SAMPLES, multiply);
    snprintf(path, sizeof(path), "%s/lmr_bb.txt",       out_dir); DUMP_INT(path, multiply, SAMPLES);

    // L-R LPF + decimation
    fir_n(multiply, SAMPLES, AUDIO_LMR_COEFFS, fir_lmr_x,
          AUDIO_LMR_COEFF_TAPS, AUDIO_DECIM, audio_lmr_filter);
    snprintf(path, sizeof(path), "%s/audio_lmr.txt",    out_dir); DUMP_INT(path, audio_lmr_filter, AUDIO_SAMPLES);

    // Stereo reconstruction
    add_n(audio_lpr_filter, audio_lmr_filter, AUDIO_SAMPLES, left);
    sub_n(audio_lpr_filter, audio_lmr_filter, AUDIO_SAMPLES, right);
    snprintf(path, sizeof(path), "%s/left_raw.txt",     out_dir); DUMP_INT(path, left, AUDIO_SAMPLES);
    snprintf(path, sizeof(path), "%s/right_raw.txt",    out_dir); DUMP_INT(path, right, AUDIO_SAMPLES);

    // De-emphasis
    deemphasis_n(left,  deemph_l_x, deemph_l_y, AUDIO_SAMPLES, left_deemph);
    deemphasis_n(right, deemph_r_x, deemph_r_y, AUDIO_SAMPLES, right_deemph);
    snprintf(path, sizeof(path), "%s/left_deemph.txt",  out_dir); DUMP_INT(path, left_deemph, AUDIO_SAMPLES);
    snprintf(path, sizeof(path), "%s/right_deemph.txt", out_dir); DUMP_INT(path, right_deemph, AUDIO_SAMPLES);

    // Volume control → final output
    gain_n(left_deemph,  AUDIO_SAMPLES, VOLUME_LEVEL, left_audio);
    gain_n(right_deemph, AUDIO_SAMPLES, VOLUME_LEVEL, right_audio);
    snprintf(path, sizeof(path), "%s/out_left.txt",     out_dir); DUMP_INT(path, left_audio, AUDIO_SAMPLES);
    snprintf(path, sizeof(path), "%s/out_right.txt",    out_dir); DUMP_INT(path, right_audio, AUDIO_SAMPLES);
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        printf("Usage: fm_golden <input.dat> <output_dir>\n");
        printf("  e.g. fm_golden test/usrp.dat test\n");
        return -1;
    }

    const char *input_file = argv[1];
    const char *out_dir    = argv[2];

    static unsigned char IQ[SAMPLES * 4];
    static int left_audio[AUDIO_SAMPLES];
    static int right_audio[AUDIO_SAMPLES];

    FILE *usrp_file = fopen(input_file, "rb");
    if (!usrp_file) { printf("Cannot open %s\n", input_file); return -1; }

    // Process only first batch for reference generation
    size_t n = fread(IQ, sizeof(char), SAMPLES * 4, usrp_file);
    fclose(usrp_file);

    if (n < (size_t)(SAMPLES * 4)) {
        printf("Warning: only read %zu / %d bytes\n", n, SAMPLES * 4);
    }

    printf("Generating golden reference from: %s\n", input_file);
    printf("Output directory: %s\n\n", out_dir);

    fm_radio_golden(IQ, left_audio, right_audio, out_dir);

    printf("\nDone. Files written to %s/\n", out_dir);
    return 0;
}
