`timescale 1ns / 1ps
module lowampa_env_tb;

    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [3:0][13:0] sq = {4*14{1'b0}};
    wire [3:0][13:0] zero = {4*14{1'b0}};

    wire [16:0] envA;
    wire [16:0] envB;

    dual_pueo_lowampa_envelope_v2b uut(.clk_i(clk),
                                       .squareA_i(sq),
                                       .squareB_i(zero),
                                       .envelopeA_o(envA),
                                       .envelopeB_o(envB));
    
    initial begin
        #300;
        @(posedge clk); 
            #0.1    sq[0] <= 14'd1;
                    sq[1] <= 14'd2;
                    sq[2] <= 14'd3;
                    sq[3] <= 14'd4;
        #300;
        @(posedge clk);
            #0.1    sq[0] <= 14'd0;
                    sq[1] <= 14'd0;
                    sq[2] <= 14'd0;
                    sq[3] <= 14'd0;                    
    end                                           
        
endmodule
