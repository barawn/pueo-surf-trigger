`timescale 1ns / 1ps
module lowampa_env_tb;

    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [3:0][13:0] sq = {4*14{1'b0}};
    wire [3:0][13:0] zero = {4*14{1'b0}};

    wire [16:0] envA;
    wire [16:0] envB;

    wire [16:0] envcA;
    wire [16:0] envcB;

    dual_pueo_lowampa_envelope_v2b uut(.clk_i(clk),
                                       .squareA_i(sq),
                                       .squareB_i(zero),
                                       .envelopeA_o(envA),
                                       .envelopeB_o(envB));

    dual_pueo_lowampa_envelope_v2c uub(.clk_i(clk),
                                       .squareA_i(sq),
                                       .squareB_i(zero),
                                       .envelopeA_o(envcA),
                                       .envelopeB_o(envcB));
    
    initial begin
        #300;
        @(posedge clk);
            #0.1    sq[0] <= 14'd6006;
                    sq[1] <= 14'd6006;
                    sq[2] <= 14'd6006;
                    sq[3] <= 14'd6006;
//        @(posedge clk); 
//            #0.1    sq[0] <= 14'd30;
//                    sq[1] <= 14'd30;
//                    sq[2] <= 14'd6;
//                    sq[3] <= 14'd2;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd2;
//                    sq[1] <= 14'd42;
//                    sq[2] <= 14'd12;
//                    sq[3] <= 14'd110;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd42;
//                    sq[1] <= 14'd42;
//                    sq[2] <= 14'd2;
//                    sq[3] <= 14'd30;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd30;
//                    sq[1] <= 14'd2;
//                    sq[2] <= 14'd42;
//                    sq[3] <= 14'd0;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd30;
//                    sq[1] <= 14'd132;
//                    sq[2] <= 14'd380;
//                    sq[3] <= 14'd272;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd240;
//                    sq[2] <= 14'd380;
//                    sq[3] <= 14'd156;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd6;
//                    sq[1] <= 14'd6;
//                    sq[2] <= 14'd0;
//                    sq[3] <= 14'd0;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd20;
//                    sq[2] <= 14'd30;
//                    sq[3] <= 14'd42;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd6;
//                    sq[1] <= 14'd30;
//                    sq[2] <= 14'd2;
//                    sq[3] <= 14'd110;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd72;
//                    sq[1] <= 14'd110;
//                    sq[2] <= 14'd110;
//                    sq[3] <= 14'd110;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd2;
//                    sq[1] <= 14'd240;
//                    sq[2] <= 14'd462;
//                    sq[3] <= 14'd306;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd132;
//                    sq[2] <= 14'd90;
//                    sq[3] <= 14'd240;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd380;
//                    sq[1] <= 14'd156;
//                    sq[2] <= 14'd20;
//                    sq[3] <= 14'd306;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd380;
//                    sq[1] <= 14'd272;
//                    sq[2] <= 14'd6;
//                    sq[3] <= 14'd56;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd56;
//                    sq[1] <= 14'd90;
//                    sq[2] <= 14'd182;
//                    sq[3] <= 14'd72;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd12;
//                    sq[1] <= 14'd132;
//                    sq[2] <= 14'd56;
//                    sq[3] <= 14'd6;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd6;
//                    sq[2] <= 14'd0;
//                    sq[3] <= 14'd2;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd6;
//                    sq[1] <= 14'd12;
//                    sq[2] <= 14'd20;
//                    sq[3] <= 14'd2;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd30;
//                    sq[1] <= 14'd56;
//                    sq[2] <= 14'd0;
//                    sq[3] <= 14'd2;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd6;
//                    sq[1] <= 14'd6;
//                    sq[2] <= 14'd30;
//                    sq[3] <= 14'd30;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd2;
//                    sq[2] <= 14'd0;
//                    sq[3] <= 14'd2;
//        @(posedge clk);
//            #0.1    sq[0] <= 14'd0;
//                    sq[1] <= 14'd0;
//                    sq[2] <= 14'd0;
//                    sq[3] <= 14'd0;




    end                                           
        
endmodule
