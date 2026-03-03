// =============================================================
// fm_radio_top_tb.sv — System-level testbench for fm_radio_top
// Input:  in_I.txt, in_Q.txt (262144 samples)
// Output: out_left.txt, out_right.txt (32768 samples)
// =============================================================

`timescale 1ns/1ps
import fir_pkg::*, qarctan_pkg::*;

module fm_radio_top_tb;

    localparam string IN_I_FILE     = "../../test/in_I.txt";
    localparam string IN_Q_FILE     = "../../test/in_Q.txt";
    localparam string GOLD_LEFT     = "../../test/out_left.txt";
    localparam string GOLD_RIGHT    = "../../test/out_right.txt";

    localparam int N_IN    = 262144;
    localparam int N_OUT   = N_IN / AUDIO_DECIM;   // 32768
    localparam int CLK_PERIOD = 10;

    logic                           clk, rst_n, valid_in;
    logic signed [WIDTH-1:0]        I_in, Q_in;
    logic                           valid_out;
    logic signed [WIDTH-1:0]        left_out, right_out;

    fm_radio_top dut (
        .clk(clk),.rst_n(rst_n),.valid_in(valid_in),
        .I_in(I_in),.Q_in(Q_in),
        .valid_out(valid_out),.left_out(left_out),.right_out(right_out));

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic signed [WIDTH-1:0] I_data     [0:N_IN-1];
    logic signed [WIDTH-1:0] Q_data     [0:N_IN-1];
    logic signed [WIDTH-1:0] gold_left  [0:N_OUT-1];
    logic signed [WIDTH-1:0] gold_right [0:N_OUT-1];

    integer l_errors, r_errors, l_checked, r_checked, l_idx, r_idx;
    integer fd, code, idx, val;

    initial begin
        $display("=== FM Radio Top-Level Testbench ===");

        // Load in_I.txt
        fd = $fopen(IN_I_FILE,"r"); if(fd==0) begin $display("ERROR: %s",IN_I_FILE); $finish; end
        idx=0; while(!$feof(fd)&&idx<N_IN) begin code=$fscanf(fd,"%d\n",val); if(code==1) begin I_data[idx]=val; idx=idx+1; end end
        $fclose(fd); $display("  Loaded %0d I samples", idx);

        // Load in_Q.txt
        fd = $fopen(IN_Q_FILE,"r"); if(fd==0) begin $display("ERROR: %s",IN_Q_FILE); $finish; end
        idx=0; while(!$feof(fd)&&idx<N_IN) begin code=$fscanf(fd,"%d\n",val); if(code==1) begin Q_data[idx]=val; idx=idx+1; end end
        $fclose(fd); $display("  Loaded %0d Q samples", idx);

        // Load out_left.txt
        fd = $fopen(GOLD_LEFT,"r"); if(fd==0) begin $display("ERROR: %s",GOLD_LEFT); $finish; end
        idx=0; while(!$feof(fd)&&idx<N_OUT) begin code=$fscanf(fd,"%d\n",val); if(code==1) begin gold_left[idx]=val; idx=idx+1; end end
        $fclose(fd); $display("  Loaded %0d left golden samples", idx);

        // Load out_right.txt
        fd = $fopen(GOLD_RIGHT,"r"); if(fd==0) begin $display("ERROR: %s",GOLD_RIGHT); $finish; end
        idx=0; while(!$feof(fd)&&idx<N_OUT) begin code=$fscanf(fd,"%d\n",val); if(code==1) begin gold_right[idx]=val; idx=idx+1; end end
        $fclose(fd); $display("  Loaded %0d right golden samples", idx);

        // Reset and drive inputs
        l_errors=0; r_errors=0; l_checked=0; r_checked=0; l_idx=0; r_idx=0;
        rst_n=0; valid_in=0; I_in=0; Q_in=0;
        @(posedge clk); @(posedge clk); rst_n=1; @(posedge clk);

        for (int i=0; i<N_IN; i++) begin
            @(posedge clk);
            valid_in = 1;
            I_in = I_data[i];
            Q_in = Q_data[i];
        end
        @(posedge clk); valid_in=0;

        // Wait for pipeline to drain (32 extra cycles for pipelined divider)
        repeat(500) @(posedge clk);

        $display("-------------------------------------------");
        $display("LEFT  : Checked=%0d Errors=%0d %s", l_checked, l_errors, (l_errors==0)?"PASS":"FAIL");
        $display("RIGHT : Checked=%0d Errors=%0d %s", r_checked, r_errors, (r_errors==0)?"PASS":"FAIL");
        $display("===========================================");
        $finish;
    end

    // Capture outputs
    always @(posedge clk) begin
        if (valid_out) begin
            if (l_idx < N_OUT) begin
                if (left_out !== gold_left[l_idx]) begin
                    if (l_errors < 10)
                        $display("L MISMATCH @%0d: got %0d, expected %0d",
                                 l_idx, left_out, gold_left[l_idx]);
                    l_errors = l_errors + 1;
                end
                l_checked = l_checked + 1;
                l_idx = l_idx + 1;
            end
            if (r_idx < N_OUT) begin
                if (right_out !== gold_right[r_idx]) begin
                    if (r_errors < 10)
                        $display("R MISMATCH @%0d: got %0d, expected %0d",
                                 r_idx, right_out, gold_right[r_idx]);
                    r_errors = r_errors + 1;
                end
                r_checked = r_checked + 1;
                r_idx = r_idx + 1;
            end
        end
    end

endmodule
