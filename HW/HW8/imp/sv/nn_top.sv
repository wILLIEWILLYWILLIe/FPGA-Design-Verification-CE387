// =============================================================
// Neural Network Top Module (Two-Process FSM)
// =============================================================
// Architecture:
//   Input FIFO → Layer 0 (784→10, ReLU) → Layer 1 (10→10, ReLU) → Argmax
//
// FSM: IDLE → FIFO_PREFETCH → START_L0 → RUN_L0 → WAIT_L0 →
//             START_L1 → RUN_L1 → WAIT_L1 → ARGMAX → DONE
// =============================================================
module nn_top
    import nn_pkg::*;
(
    input  logic                          clk,
    input  logic                          reset,

    // Input FIFO write interface
    input  logic                          wr_en,
    input  logic signed [DATA_WIDTH-1:0]  din,
    output logic                          in_full,

    // Output
    output logic                          inference_done,
    output logic [3:0]                    predicted_class,
    output logic signed [DATA_WIDTH-1:0]  max_score
);

    // =========================================================
    // File path localparams (relative to working directory)
    // =========================================================
    localparam string L0_BIAS_FILE = "../source/layer0_biases.txt";
    localparam string L1_BIAS_FILE = "../source/layer1_biases.txt";

    // =========================================================
    // Input FIFO (need >= 784 entries)
    // =========================================================
    logic                          fifo_rd_en;
    logic signed [DATA_WIDTH-1:0]  fifo_dout;
    logic signed [DATA_WIDTH-1:0]  fifo_dout_reg;  // registered output (isolate BRAM delay)
    logic                          fifo_empty;

    fifo #(
        .FIFO_DATA_WIDTH  (DATA_WIDTH),
        .FIFO_BUFFER_SIZE (16)
    ) u_input_fifo (
        .reset  (reset),
        .wr_clk (clk),
        .wr_en  (wr_en),
        .din    (din),
        .full   (in_full),
        .rd_clk (clk),
        .rd_en  (fifo_rd_en),
        .dout   (fifo_dout),
        .empty  (fifo_empty)
    );

    // Register FIFO output to isolate BRAM clock-to-output delay
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            fifo_dout_reg <= '0;
        else
            fifo_dout_reg <= fifo_dout;
    end

    // =========================================================
    // Layer 0: 10 neurons × 784 inputs
    // =========================================================
    logic                          l0_start;
    logic                          l0_valid_in;
    logic signed [DATA_WIDTH-1:0]  l0_data_in;
    logic                          l0_valid_out;
    logic signed [DATA_WIDTH-1:0]  l0_relu [10];

    layer #(
        .NUM_NEURONS   (LAYER0_OUT),
        .INPUT_SIZE    (LAYER0_IN),
        .LAYER_ID      (0),
        .BIAS_FILE     ("../source/layer0_biases.txt")
    ) u_layer0 (
        .clk       (clk),
        .reset     (reset),
        .start     (l0_start),
        .valid_in  (l0_valid_in),
        .data_in   (l0_data_in),
        .valid_out (l0_valid_out),
        .results   (l0_relu)
    );

    // =========================================================
    // Layer 1: 10 neurons × 10 inputs
    // =========================================================
    logic                          l1_start;
    logic                          l1_valid_in;
    logic signed [DATA_WIDTH-1:0]  l1_data_in;
    logic                          l1_valid_out;
    logic signed [DATA_WIDTH-1:0]  l1_relu [10];

    layer #(
        .NUM_NEURONS   (LAYER1_OUT),
        .INPUT_SIZE    (LAYER1_IN),
        .LAYER_ID      (1),
        .BIAS_FILE     ("../source/layer1_biases.txt")
    ) u_layer1 (
        .clk       (clk),
        .reset     (reset),
        .start     (l1_start),
        .valid_in  (l1_valid_in),
        .data_in   (l1_data_in),
        .valid_out (l1_valid_out),
        .results   (l1_relu)
    );

    // =========================================================
    // Argmax (iterative — 1 compare per cycle)
    // =========================================================
    logic                          argmax_start;
    logic signed [DATA_WIDTH-1:0]  argmax_scores [10];
    logic                          argmax_valid_out;
    logic [3:0]                    argmax_class;
    logic signed [DATA_WIDTH-1:0]  argmax_score;

    argmax #(.NUM_CLASSES(10)) u_argmax (
        .clk             (clk),
        .reset           (reset),
        .start           (argmax_start),
        .scores          (argmax_scores),
        .valid_out       (argmax_valid_out),
        .predicted_class (argmax_class),
        .max_score       (argmax_score)
    );

    // =========================================================
    // FSM (Two-Process)
    // =========================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_FIFO_PREFETCH,
        S_START_L0,
        S_RUN_L0,
        S_WAIT_L0,
        S_START_L1,
        S_RUN_L1,
        S_WAIT_L1,
        S_ARGMAX,
        S_DONE
    } state_t;

    // State registers
    state_t                                state,      state_next;
    logic [$clog2(NUM_INPUTS+1)-1:0]       cnt,        cnt_next;
    logic [3:0]                            l1_cnt,     l1_cnt_next;
    logic signed [DATA_WIDTH-1:0]          l0_result [10];
    logic signed [DATA_WIDTH-1:0]          l0_result_next [10];
    logic signed [DATA_WIDTH-1:0]          l1_result [10];
    logic signed [DATA_WIDTH-1:0]          l1_result_next [10];
    logic                                  inf_done_r, inf_done_next;
    logic [3:0]                            pred_r,     pred_next;
    logic signed [DATA_WIDTH-1:0]          mscore_r,   mscore_next;

    // ---------------------------------------------------------
    // Process 1: Combinational next-state + output logic
    // ---------------------------------------------------------
    always_comb begin
        // Defaults: hold state, clear pulse signals
        state_next      = state;
        cnt_next        = cnt;
        l1_cnt_next     = l1_cnt;
        inf_done_next   = 1'b0;
        pred_next       = pred_r;
        mscore_next     = mscore_r;

        l0_start        = 1'b0;
        l0_valid_in     = 1'b0;
        l0_data_in      = '0;
        l1_start        = 1'b0;
        l1_valid_in     = 1'b0;
        l1_data_in      = '0;
        argmax_start    = 1'b0;
        fifo_rd_en      = 1'b0;

        for (int i = 0; i < 10; i++) begin
            l0_result_next[i]  = l0_result[i];
            l1_result_next[i]  = l1_result[i];
            argmax_scores[i]   = l1_result[i];
        end

        case (state)
            S_IDLE: begin
                if (!fifo_empty) begin
                    fifo_rd_en = 1'b1;
                    state_next = S_FIFO_PREFETCH;
                end
            end

            S_FIFO_PREFETCH: begin
                state_next = S_START_L0;
            end

            S_START_L0: begin
                l0_start   = 1'b1;
                cnt_next   = '0;
                fifo_rd_en = 1'b1;    // pre-fetch: compensate for fifo_dout_reg latency
                state_next = S_RUN_L0;
            end

            S_RUN_L0: begin
                l0_valid_in = 1'b1;
                l0_data_in  = fifo_dout_reg;  // use registered FIFO output
                cnt_next    = cnt + 1;

                if (cnt < NUM_INPUTS - 2)     // stop 1 earlier (compensate pre-fetch)
                    fifo_rd_en = 1'b1;

                if (cnt == NUM_INPUTS - 1)
                    state_next = S_WAIT_L0;
            end

            S_WAIT_L0: begin
                if (l0_valid_out) begin
                    for (int i = 0; i < 10; i++)
                        l0_result_next[i] = l0_relu[i];
                    state_next = S_START_L1;
                end
            end

            S_START_L1: begin
                l1_start    = 1'b1;
                l1_cnt_next = '0;
                state_next  = S_RUN_L1;
            end

            S_RUN_L1: begin
                l1_valid_in = 1'b1;
                l1_data_in  = l0_result[l1_cnt];
                l1_cnt_next = l1_cnt + 1;

                if (l1_cnt == LAYER1_IN - 1)
                    state_next = S_WAIT_L1;
            end

            S_WAIT_L1: begin
                if (l1_valid_out) begin
                    for (int i = 0; i < 10; i++)
                        l1_result_next[i] = l1_relu[i];
                    state_next = S_ARGMAX;
                end
            end

            S_ARGMAX: begin
                argmax_start = 1'b1;
                for (int i = 0; i < 10; i++)
                    argmax_scores[i] = l1_result[i];
                state_next = S_DONE;
            end

            S_DONE: begin
                if (argmax_valid_out) begin
                    pred_next     = argmax_class;
                    mscore_next   = argmax_score;
                    inf_done_next = 1'b1;
                    state_next    = S_IDLE;
                end
            end

            default: state_next = S_IDLE;
        endcase
    end

    // ---------------------------------------------------------
    // Process 2: Sequential state register update
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= S_IDLE;
            cnt      <= '0;
            l1_cnt   <= '0;
            inf_done_r <= 1'b0;
            pred_r   <= '0;
            mscore_r <= '0;
            for (int i = 0; i < 10; i++) begin
                l0_result[i] <= '0;
                l1_result[i] <= '0;
            end
        end else begin
            state    <= state_next;
            cnt      <= cnt_next;
            l1_cnt   <= l1_cnt_next;
            inf_done_r <= inf_done_next;
            pred_r   <= pred_next;
            mscore_r <= mscore_next;
            for (int i = 0; i < 10; i++) begin
                l0_result[i] <= l0_result_next[i];
                l1_result[i] <= l1_result_next[i];
            end
        end
    end

    assign inference_done  = inf_done_r;
    assign predicted_class = pred_r;
    assign max_score       = mscore_r;

endmodule
