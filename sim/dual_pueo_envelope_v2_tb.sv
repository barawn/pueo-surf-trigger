`timescale 1ns / 1ps
module dual_pueo_envelope_v2_tb;

    wire clk;
    tb_rclk #(.PERIOD(10)) u_clk(.clk(clk));
    
    reg [7:0][13:0] sq = {8*14{1'b0}};
    wire [16:0] envelopeA;
    wire [16:0] envelopeB;
    dual_pueo_envelope_v2 uut(.clk_i(clk),
                              .squareA_i(sq),
                              .squareB_i(sq),
                              .envelopeA_o(envelopeA),
                              .envelopeB_o(envelopeB));
    wire [18*2-1:0] envelopes = { {1'b0,envelopeB}, 
                                  {1'b0,envelopeA} };
    reg [1:0][17:0] thresholds = {18*2{1'b0}};                                  
    reg [1:0] thresh_wr = {2{1'b0}};
    reg [1:0] thresh_update = {2{1'b0}};
    wire [3:0] trigger;
    dual_pueo_threshold_v2 #(.CASCADE("FALSE"))
                           uutB(.clk_i(clk),
                                .thresh_i(thresholds),
                                .thresh_wr_i(thresh_wr),
                                .thresh_update_i(thresh_update),
                                .envelope_i(envelopes),
                                .trigger_o(trigger));                                                                 

    initial begin
        #100;
        @(posedge clk);
            // LAST threshold gets written FIRST
            #0.1 thresholds[0] = 10;    // this is a thresh of 190
                 thresholds[1] = 20;    // this is a thresh of 180
                 thresh_wr = 2'b11;
        @(posedge clk);
            #0.1 thresholds[0] = 200;
                 thresholds[1] = 200;
        @(posedge clk); // last thresholds in A1 reg...
            #0.1 thresh_wr = 2'b00;
        @(posedge clk); // last thresholds now in next DSP A1 reg
                        // so we wait NBEAMS clocks
            #0.1 thresh_update = 2'b11;                        
        @(posedge clk);
            #0.1 thresh_update = 2'b00;
        
        #100;                          
        @(posedge clk);
            #0.1 sq[0] = 1;
                 sq[1] = 4;
                 sq[2] = 9;
                 sq[3] = 16; // sums to 30
                 sq[4] = 25;
                 sq[5] = 36;
                 sq[6] = 49;
                 sq[7] = 64; // sums to 174
        @(posedge clk);
            #0.1 sq[0] = 0;
                 sq[1] = 0;
                 sq[3] = 0;
                 sq[4] = 0;
                 sq[5] = 0;
                 sq[6] = 0;
                 sq[7] = 0;
    end                              

endmodule
