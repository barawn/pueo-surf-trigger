`timescale 1ns / 1ps
`include "dsp_macros.vh"
// This module forms the envelope signal, which is what
// we threshold on.
// The current version is equivalent to a sum of 8 samples
// computed every 4, or
// (sum[3:0] + sum[7:4]z^-1)
// (sum[3:0] + sum[7:4])
// Except this module only outputs the GREATER of those two.
//
// This is also equivalent to a FIR filter of [1,1,1,1,1,1,1,1]
// followed by a decimation by 4 and then a max of those 2.
module dual_pueo_lowampa_envelope_v2 #(localparam NBITS=14,
                               localparam NSAMP=4,
                               localparam OUTBITS=17,
			       localparam STORE_LENGTH = 15)(
        input clk_i,
        input [NBITS*NSAMP-1:0] squareA_i,
        input [NBITS*NSAMP-1:0] squareB_i,
        
        output [OUTBITS-1:0] envelopeA_o,
        output [OUTBITS-1:0] envelopeB_o        
    );
    
    // I have lots o' doubts about the right way to do this, sigh.
    // Sum of 4 fundamentally sucks. 

    // LET ME JUST TEST TO SEE IF THIS SHIT WORKS AT ALL
    wire [3:0][NBITS-1:0] sqA_in = squareA_i;
    wire [3:0][NBITS-1:0] sqB_in = squareB_i;
    wire [3:0][NBITS-1:0] sqA_30 = { sqA_in[3],
                                     sqA_in[2],
                                     sqA_in[1],
                                     sqA_in[0] };
    wire [3:0][NBITS-1:0] sqB_30 = { sqB_in[3],
                                     sqB_in[2],
                                     sqB_in[1],
                                     sqB_in[0] };
     
    // these are the generated low 3 bits for the [3:0] sum
    wire [2:0] lowbit30_A;
    wire [2:0] lowbit30_B;
    // these are the 4 compressed low bit inputs to the DSPs for [3:0] sum
    wire [3:0] bit2_compress30_A;
    wire [3:0] bit2_compress30_B;

    // the 4th input is just passed through, the 1st input is
    // derived from a LUT5, and the 2nd and 3rd in a LUT6_2
    `define BIT2_CMPR( name, in, out )        \
        assign out[3] = in[3][3];       \
        LUT5 #(.INIT(32'hFFFF8228))     \
     name``_bit3_0 (.I4(in[0][3]),        \
                  .I3(in[3][2]),        \
                  .I2(in[2][2]),        \
                  .I1(in[1][2]),        \
                  .I0(in[0][2]),        \
                  .O(out[0]));          \
        LUT6_2 #(.INIT(64'hFFFFC0C0_FF28FF28))  \
     name``_bit3_12 (.I5(1'b1),         \
                     .I4( in[2][3] ),   \
                     .I3( in[1][3] ),   \
                     .I2( in[3][2] ),   \
                     .I1( in[2][2] ),   \
                     .I0( in[1][2] ),   \
                     .O6( out[2] ),     \
                     .O5( out[1] ))
    
    `define LOWBIT_LUT( name, in, out )     \
        LUT6_2 #(.INIT(64'h7EE87EE8_69966996))  \
    name``_lowbit_lut0 (.I5(1'b1),          \
                        .I4(1'b0),          \
                        .I3( in[3][0] ),    \
                        .I2( in[2][0] ),    \
                        .I1( in[1][0] ),    \
                        .I0( in[0][0] ),    \
                        .O5( out[0] ),      \
                        .O6( out[1] ));     \
        wire name``_lowbit_carry = in[3][0] && in[2][0] && in[1][0] && in[0][0];  \
        assign out[2] = in[3][2] ^ in[2][2] ^ in[1][2] ^ in[0][2] ^ name``_lowbit_carry

    // generate the low bits
    `LOWBIT_LUT( lb30_A , sqA_30, lowbit30_A );
    `LOWBIT_LUT( lb30_B , sqB_30, lowbit30_B );
    
    // compress the carry from the bottom 
    `BIT2_CMPR( cmpr30_A , sqA_30, bit2_compress30_A );
    `BIT2_CMPR( cmpr30_B , sqB_30, bit2_compress30_B );

    wire [3:0][11:0] dspinA_30= {{1'b0, sqA_30[3][4 +: 10], bit2_compress30_A[3] },
                                 {1'b0, sqA_30[2][4 +: 10], bit2_compress30_A[2] },
                                 {1'b0, sqA_30[1][4 +: 10], bit2_compress30_A[1] },
                                 {1'b0, sqA_30[0][4 +: 10], bit2_compress30_A[0] } };


    wire [3:0][11:0] dspinB_30= {{1'b0, sqB_30[3][4 +: 10], bit2_compress30_B[3] },
                                 {1'b0, sqB_30[2][4 +: 10], bit2_compress30_B[2] },
                                 {1'b0, sqB_30[1][4 +: 10], bit2_compress30_B[1] },
                                 {1'b0, sqB_30[0][4 +: 10], bit2_compress30_B[0] } };


    // We now only have 11 bit objects, and therefore we can add 4 of them.
    wire [47:0] cascade;
    wire [47:0] out;
    wire [3:0][11:0] dsp_out = out;
    wire [3:0] test_carry;
    // four12_dsp trims the reset and CE by default
    four12_dsp #(.PREG(0))
               u_dspA(.clk_i(clk_i),
                      .AB_i( { 12'b0, dspinB_30[0], 12'b0, dspinA_30[0] } ),
                      .C_i(  { 12'b0, dspinB_30[1], 12'b0, dspinA_30[1] } ),
                      .pc_o( cascade ) );
    four12_dsp #(.CASCADE("TRUE"),
                 .OPMODE({2'b00, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB}))
                 u_dspB(.clk_i(clk_i),
                      .AB_i( { 12'b0, dspinB_30[2], 12'b0, dspinA_30[2] } ),
                      .C_i(  { 12'b0, dspinB_30[3], 12'b0, dspinA_30[3] } ),
                        .P_o( out ),
                        .pc_i( cascade ),
                        .CARRY_o( test_carry ) );                                       
    
    // This is an annoying quirk in HDL - you can't really get the carry of a subtract
    // operation, so pipelining it is a giant disaster. 

    // Since we can't actually use the subtractor due to HDL quirkiness, we have to do
    // the math ourselves.
    
    wire [13:0] sum30_A = {test_carry[0], dsp_out[0]};
    wire [13:0] sum30_B = {test_carry[2], dsp_out[2]};    

    // We delay sum30_A by 3 and the lowbit store by 4 to line them up.
    (* SRL_STYLE = "srl_reg" *)
    reg [1:0][13:0] sum30_A_shreg = {3*14{1'b0}};
    (* SRL_STYLE = "srl_reg" *)
    reg [3:0][2:0] lowbit30_A_shreg = {5*3{1'b0}};

    (* SRL_STYLE = "srl_reg" *)
    reg [1:0][13:0] sum30_B_shreg = {3*14{1'b0}};
    (* SRL_STYLE = "srl_reg" *)
    reg [3:0][2:0] lowbit30_B_shreg = {5*3{1'b0}};
            
    wire [15:0] sq_sum30_A;
    wire [15:0] sq_sum30_B;

    (* SRL_STYLE = "srl_reg" *)
    reg  [1:0][STORE_LENGTH-1:0][23:0] sq_sum_store = 0;
    
    always @(posedge clk_i) begin
        sum30_A_shreg[0] <= sum30_A;
        sum30_A_shreg[1] <= sum30_A_shreg[0];

        lowbit30_A_shreg[0] <= lowbit30_A;
        lowbit30_A_shreg[1] <= lowbit30_A_shreg[0];
        lowbit30_A_shreg[2] <= lowbit30_A_shreg[1];
        lowbit30_A_shreg[3] <= lowbit30_A_shreg[2];

        sum30_B_shreg[0] <= sum30_B;
        sum30_B_shreg[1] <= sum30_B_shreg[0];

        lowbit30_B_shreg[0] <= lowbit30_B;
        lowbit30_B_shreg[1] <= lowbit30_B_shreg[0];
        lowbit30_B_shreg[2] <= lowbit30_B_shreg[1];
        lowbit30_B_shreg[3] <= lowbit30_B_shreg[2];

	sq_sum_store[0][0] <= sq_sum30_A; 
	sq_sum_store[0][1] <= sq_sum_store[0][0]; 
	sq_sum_store[0][2] <= sq_sum_store[0][1]; 
	sq_sum_store[0][3] <= sq_sum_store[0][2]; 
	sq_sum_store[0][4] <= sq_sum_store[0][3]; 
	sq_sum_store[0][5] <= sq_sum_store[0][4]; 
	sq_sum_store[0][6] <= sq_sum_store[0][5]; 
	sq_sum_store[0][7] <= sq_sum_store[0][6]; 
	sq_sum_store[0][8] <= sq_sum_store[0][7]; 
	sq_sum_store[0][9] <= sq_sum_store[0][8]; 
	sq_sum_store[0][10] <= sq_sum_store[0][9]; 
	sq_sum_store[0][11] <= sq_sum_store[0][10]; 
	sq_sum_store[0][12] <= sq_sum_store[0][11]; 
	sq_sum_store[0][13] <= sq_sum_store[0][12]; 
	sq_sum_store[0][14] <= sq_sum_store[0][13]; 

	sq_sum_store[1][0] <= sq_sum30_B; 
	sq_sum_store[1][1] <= sq_sum_store[1][0]; 
	sq_sum_store[1][2] <= sq_sum_store[1][1]; 
	sq_sum_store[1][3] <= sq_sum_store[1][2]; 
	sq_sum_store[1][4] <= sq_sum_store[1][3]; 
	sq_sum_store[1][5] <= sq_sum_store[1][4]; 
	sq_sum_store[1][6] <= sq_sum_store[1][5]; 
	sq_sum_store[1][7] <= sq_sum_store[1][6]; 
	sq_sum_store[1][8] <= sq_sum_store[1][7]; 
	sq_sum_store[1][9] <= sq_sum_store[1][8]; 
	sq_sum_store[1][10] <= sq_sum_store[1][9]; 
	sq_sum_store[1][11] <= sq_sum_store[1][10]; 
	sq_sum_store[1][12] <= sq_sum_store[1][11]; 
	sq_sum_store[1][13] <= sq_sum_store[1][12]; 
	sq_sum_store[1][14] <= sq_sum_store[1][13]; 
    end

    assign sq_sum30_A = { sum30_A_shreg[1], lowbit30_A_shreg[3] };
    assign sq_sum30_B = { sum30_B_shreg[1], lowbit30_B_shreg[3] };

    // now we stick everything into an SRL, and adjust the length
    // to line up based on use_undelayed_A.
    
    // and now FINALLY we add it up in the two24
    //wire [1:0][23:0] final_dsp_out;
    //two24_dsp u_dsp(.clk_i(clk_i),
    //                .AB_i({ {8{1'b0}}, sq_sum30_B, {8{1'b0}}, sq_sum30_A }),
    //                .C_i( { {8{1'b0}}, sq_sum74_B, {8{1'b0}}, sq_sum74_A }),
    //                .P_o( final_dsp_out ));
    
    //we want A+D-C with A=current total, B=new square sum, C= oldest Square sum
    wire [1:0][23:0] running_total;
    wire [1:0][23:0] add_total;
    reg  [1:0][23:0] running_total_reg = 0;
    wire [1:0][23:0] final_total;
    
    two24_dsp #(.ABREG(1),
	        .CREG(1),
		.PREG(0)) 
            add_dsp(.clk_i(clk_i),
                    .AB_i({ {8{1'b0}}, sq_sum30_B, {8{1'b0}}, sq_sum30_A }),
                    .C_i( { running_total_reg[1], running_total_reg[0] }),
                    .P_o( { add_total[1], add_total[0] }));

    //C delayed by 1 in above
    //C-AB 
    wire [47:0] to_final;
    two24_dsp #(.ABREG(1),
                .CREG(0),
		.PREG(0),
	        .ALUMODE(`ALUMODE_Z_MINUS_XYCIN))
                    sub_dsp(
                    .clk_i(clk_i),
                    .C_i({ add_total[1], add_total[0] }),
                    .AB_i( { {8{1'b0}}, sq_sum_store[1][12], {8{1'b0}}, sq_sum_store[0][12] }), //12*4 samples sets = 48s (32ns at 1.5GHZ) 
                    .P_o( {running_total[1], running_total[0]} ));

    always@(posedge clk_i)
    begin
      running_total_reg <= running_total;
    end
    
    two24_dsp #(.ABREG(1),
                .CREG(1),
		        .PREG(0))
                    final_dsp(
                    .clk_i(clk_i),
                    .C_i({running_total[1], running_total[0]}),
                    .AB_i( {running_total_reg[1], running_total_reg[0]}),
                    .P_o( {final_total[1], final_total[0]} ));

   //16 bit sq_sum, 2->17, 4->18, 8->19, 16->20 

    assign envelopeA_o = final_total[0][19:3];
    assign envelopeB_o = final_total[1][19:3];            
endmodule
