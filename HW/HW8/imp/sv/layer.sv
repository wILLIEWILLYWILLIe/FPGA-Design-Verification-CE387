// =============================================================
// Parameterized Dense Layer Module
// =============================================================
// Encapsulates NUM_NEURONS neurons with bias ROM and ReLU.
// Each neuron loads its weights from:
//   {WEIGHT_PREFIX}{i}_weights.txt
//
// Parameters:
//   NUM_NEURONS   — number of neurons in this layer
//   INPUT_SIZE    — number of inputs per neuron
//   WEIGHT_PREFIX — path prefix for weight files
//   BIAS_FILE     — path to bias hex file
// =============================================================
module layer
    import nn_pkg::*;
#(
    parameter int    NUM_NEURONS   = 10,
    parameter int    INPUT_SIZE    = 784,
    parameter int    LAYER_ID      = 0,
    parameter string BIAS_FILE     = "../source/layer0_biases.txt"
)
(
    input  logic                          clk,
    input  logic                          reset,
    input  logic                          start,
    input  logic                          valid_in,
    input  logic signed [DATA_WIDTH-1:0]  data_in,
    output logic                          valid_out,
    output logic signed [DATA_WIDTH-1:0]  results [0:NUM_NEURONS-1]
);

    // ---------------------------------------------------------
    // Bias ROM
    // ---------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] biases [0:NUM_NEURONS-1];
    initial $readmemh(BIAS_FILE, biases);

    // ---------------------------------------------------------
    // Neuron array (generate loop)
    // ---------------------------------------------------------
    logic                          neuron_valid [NUM_NEURONS];
    logic signed [DATA_WIDTH-1:0]  neuron_out   [NUM_NEURONS];

    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i++) begin : gen_neurons
            if (LAYER_ID == 0) begin : l0
                if (i == 0) begin : n0
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron0_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 1) begin : n1
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron1_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 2) begin : n2
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron2_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 3) begin : n3
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron3_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 4) begin : n4
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron4_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 5) begin : n5
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron5_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 6) begin : n6
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron6_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 7) begin : n7
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron7_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 8) begin : n8
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron8_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 9) begin : n9
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer0_neuron9_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end
            end else if (LAYER_ID == 1) begin : l1
                if (i == 0) begin : n0
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron0_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 1) begin : n1
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron1_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 2) begin : n2
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron2_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 3) begin : n3
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron3_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 4) begin : n4
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron4_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 5) begin : n5
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron5_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 6) begin : n6
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron6_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 7) begin : n7
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron7_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 8) begin : n8
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron8_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end else if (i == 9) begin : n9
                    neuron #(.INPUT_SIZE(INPUT_SIZE), .WEIGHT_FILE("../source/layer1_neuron9_weights.txt")) u_n(
                        .clk(clk), .reset(reset), .start(start), .bias(biases[i]), .valid_in(valid_in), .data_in(data_in), .valid_out(neuron_valid[i]), .data_out(neuron_out[i]));
                end
            end
        end
    endgenerate

    // ---------------------------------------------------------
    // ReLU activation (combinational)
    // ---------------------------------------------------------
    assign valid_out = neuron_valid[0];

    always_comb begin
        for (int j = 0; j < NUM_NEURONS; j++)
            results[j] = (neuron_out[j] > 0) ? neuron_out[j] : '0;
    end

endmodule
