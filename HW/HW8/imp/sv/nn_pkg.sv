// =============================================================
// Neural Network Parameter Package
// =============================================================
package nn_pkg;

    // --- Quantization ---
    parameter BITS       = 14;
    parameter QUANT_VAL  = (1 << BITS);   // 16384

    // --- Data Width ---
    parameter DATA_WIDTH = 32;

    // --- Network Topology ---
    parameter NUM_LAYERS   = 2;
    parameter NUM_INPUTS   = 784;   // 28x28 MNIST
    parameter NUM_OUTPUTS  = 10;    // digits 0-9

    // Layer sizes
    parameter LAYER0_IN  = 784;
    parameter LAYER0_OUT = 10;
    parameter LAYER1_IN  = 10;
    parameter LAYER1_OUT = 10;

    // Maximum across layers (for parameterized sizing)
    parameter MAX_INPUT_SIZE  = 784;
    parameter MAX_OUTPUT_SIZE = 10;
    parameter MAX_WEIGHTS     = 7840;  // 784 * 10

    // --- FIFO ---
    parameter FIFO_DEPTH = 16;

    // --- Debug ---
    parameter DEBUG = 1;

    // --- Dequantize function (truncate toward zero, matching C `/`) ---
    function automatic signed [DATA_WIDTH-1:0] dequantize;
        input signed [2*DATA_WIDTH-1:0] product;
        logic signed [2*DATA_WIDTH-1:0] adjusted;
        begin
            if (product < 0)
                adjusted = product + QUANT_VAL - 1;
            else
                adjusted = product;
            dequantize = adjusted >>> BITS;
        end
    endfunction

endpackage
