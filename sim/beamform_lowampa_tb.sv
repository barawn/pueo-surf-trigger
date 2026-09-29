`timescale 1ns / 1ps
module beamform_lowampa_tb;

    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [4:0][3:0][4:0] samples = {5*4{5'd16}};

    wire [4*8-1:0] beam_raw;
    wire [3:0][7:0] beam = {
        ~beam_raw[31], beam_raw[3*8 +: 7],
        ~beam_raw[23], beam_raw[2*8 +: 7],
        ~beam_raw[15], beam_raw[1*8 +: 7],
        ~beam_raw[7], beam_raw[0*8 +: 7] };
    beamform_lowampa uut(.clk_i(clk),
                         .A(samples[0]),
                         .B(samples[1]),
                         .C(samples[2]),
                         .D(samples[3]),
                         .E(samples[4]),
                         .O(beam_raw));
                         
    initial begin
        #100;
        
        @(posedge clk); #0.1;
            samples[0][0] = 5'd17; // 1     -- really 1.5
            samples[1][0] = 5'd15; // -1    -- really -0.5
            samples[2][0] = 5'd23; // 7     -- really 7.5
            samples[3][0] = 5'd4;  // -12   -- really -11.5
            samples[4][0] = 5'd30; // 14    -- really 14.5
                                //         should sum to 11 I think.
                                //         Raw output should be 139, then flip top bit = 11
                                //         True output is 11.5, but the 0.5 is not representable so
                                //         we deal with it later. 
        @(posedge clk); #0.1;
            samples[0][0] = 5'd16;
            samples[1][0] = 5'd16;
            samples[2][0] = 5'd16;
            samples[3][0] = 5'd16;
            samples[4][0] = 5'd16;
    end                

endmodule
