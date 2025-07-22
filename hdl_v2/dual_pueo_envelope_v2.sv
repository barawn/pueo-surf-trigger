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
module dual_pueo_envelope_v2 #(localparam NBITS=14,
                               localparam NSAMP=8,
                               localparam OUTBITS=17)(
        input clk_i,
        input [NBITS*NSAMP-1:0] squareA_i,
        input [NBITS*NSAMP-1:0] squareB_i,
        
        output [OUTBITS-1:0] envelopeA_o,
        output [OUTBITS-1:0] envelopeB_o        
    );
    
    // I have lots o' doubts about the right way to do this, sigh.
    // Sum of 4 fundamentally sucks. 

    // LET ME JUST TEST TO SEE IF THIS SHIT WORKS AT ALL
    wire [7:0][NBITS-1:0] sqA_in = squareA_i;
    wire [7:0][NBITS-1:0] sqB_in = squareB_i;
    wire [3:0][NBITS-1:0] sqA_74 = { sqA_in[7],
                                     sqA_in[6],
                                     sqA_in[5],
                                     sqA_in[4] };
    wire [3:0][NBITS-1:0] sqA_30 = { sqA_in[3],
                                     sqA_in[2],
                                     sqA_in[1],
                                     sqA_in[0] };
    wire [3:0][NBITS-1:0] sqB_74 = { sqB_in[7],
                                     sqB_in[6],
                                     sqB_in[5],
                                     sqB_in[4] };
    wire [3:0][NBITS-1:0] sqB_30 = { sqB_in[3],
                                     sqB_in[2],
                                     sqB_in[1],
                                     sqB_in[0] };
     
    // these are the generated low 3 bits for the [3:0] sum
    wire [2:0] lowbit30_A;
    wire [2:0] lowbit30_B;
    // these are the generated low 3 bits for the [7:4] sum
    wire [2:0] lowbit74_A;
    wire [2:0] lowbit74_B;
    // these are the 4 compressed low bit inputs to the DSPs for [3:0] sum
    wire [3:0] bit2_compress30_A;
    wire [3:0] bit2_compress30_B;
    // these are the 4 compressed low bit inputs to the DSPs for [7:4] sum
    wire [3:0] bit2_compress74_A;
    wire [3:0] bit2_compress74_B;

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
        assign name``_lowbit_carry = in[3][0] && in[2][0] && in[1][0] && in[0][0];  \
        assign out[2] = in[3][2] ^ in[2][2] ^ in[1][2] ^ in[0][2] ^ name``_lowbit_carry

    // generate the low bits
    `LOWBIT_LUT( lb74_A , sqA_74, lowbit74_A );
    `LOWBIT_LUT( lb30_A , sqA_30, lowbit30_A );
    `LOWBIT_LUT( lb74_B , sqB_74, lowbit74_B );
    `LOWBIT_LUT( lb30_B , sqB_30, lowbit30_B );
    
    // compress the carry from the bottom 
    `BIT2_CMPR( cmpr74_A , sqA_74, bit2_compress74_A );
    `BIT2_CMPR( cmpr30_A , sqA_30, bit2_compress30_A );
    `BIT2_CMPR( cmpr74_B , sqB_74, bit2_compress74_B );
    `BIT2_CMPR( cmpr30_B , sqB_30, bit2_compress30_B );

    wire [3:0][11:0] dspinA_30= {{1'b0, sqA_30[3][4 +: 10], bit2_compress30_A[3] },
                                 {1'b0, sqA_30[2][4 +: 10], bit2_compress30_A[2] },
                                 {1'b0, sqA_30[1][4 +: 10], bit2_compress30_A[1] },
                                 {1'b0, sqA_30[0][4 +: 10], bit2_compress30_A[0] } };

    wire [3:0][11:0] dspinA_74= {{1'b0, sqA_74[3][4 +: 10], bit2_compress74_A[3] },
                                 {1'b0, sqA_74[2][4 +: 10], bit2_compress74_A[2] },
                                 {1'b0, sqA_74[1][4 +: 10], bit2_compress74_A[1] },
                                 {1'b0, sqA_74[0][4 +: 10], bit2_compress74_A[0] } };

    wire [3:0][11:0] dspinB_30= {{1'b0, sqB_30[3][4 +: 10], bit2_compress30_B[3] },
                                 {1'b0, sqB_30[2][4 +: 10], bit2_compress30_B[2] },
                                 {1'b0, sqB_30[1][4 +: 10], bit2_compress30_B[1] },
                                 {1'b0, sqB_30[0][4 +: 10], bit2_compress30_B[0] } };

    wire [3:0][11:0] dspinB_74= {{1'b0, sqB_74[3][4 +: 10], bit2_compress74_B[3] },
                                 {1'b0, sqB_74[2][4 +: 10], bit2_compress74_B[2] },
                                 {1'b0, sqB_74[1][4 +: 10], bit2_compress74_B[1] },
                                 {1'b0, sqB_74[0][4 +: 10], bit2_compress74_B[0] } };

    // We now only have 11 bit objects, and therefore we can add 4 of them.
    wire [47:0] cascade;
    wire [47:0] out;
    wire [3:0][11:0] dsp_out = out;
    wire [3:0] test_carry;
    // four12_dsp trims the reset and CE by default
    four12_dsp #(.PREG(0))
               u_dspA(.clk_i(clk_i),
                      .AB_i( { dspinB_74[0], dspinB_30[0], dspinA_74[0], dspinA_30[0] } ),
                      .C_i(  { dspinB_74[1], dspinB_30[1], dspinA_74[1], dspinA_30[1] } ),
                      .pc_o( cascade ) );
    four12_dsp #(.CASCADE("TRUE"),
                 .OPMODE({2'b00, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB}))
                 u_dspB(.clk_i(clk_i),
                      .AB_i( { dspinB_74[2], dspinB_30[2], dspinA_74[2], dspinA_30[2] } ),
                      .C_i(  { dspinB_74[3], dspinB_30[3], dspinA_74[3], dspinA_30[3] } ),
                        .P_o( out ),
                        .pc_i( cascade ),
                        .CARRY_o( test_carry ) );                                       
    
    // for lowbit_store74, we want to do a difference between it and the prior, and
    // store the carry. that will get fed into the larger compare.
    // That then selects between the address bits on the SRL that aligns everything
    // into the final 24-bit adder.
    // Because synthesizers are stupid, we need to complete stuff ourselves at the top.

    reg [2:0] lowbit_store74_A = {3{1'b0}};
    reg [2:0] lowbit_store74_B = {3{1'b0}};

    // This is an annoying quirk in HDL - you can't really get the carry of a subtract
    // operation, so pipelining it is a giant disaster. 
    // Timing wise what we end up wanting is "use lowbitz^-1" but recall that
    // you think the carry from a < b gets you 1 if (a-b) < 0 (meaning b >= a),
    // but the carry actually gets you not that value:
    // e.g. if a is 3 and b is 1, you have 011 + 110 + 1 = 1010.
    // e.g. the carry from a - b gets you a >= b.
    // so we want a = lowbitz^-1 and b = lowbit

    // Since we can't actually use the subtractor due to HDL quirkiness, we have to do
    // the math ourselves.
    
    wire [3:0] lowbit_store74_diffA = {1'b0, lowbit_store74_A} + {1'b0, lowbit74_A} + 1'b1;
    reg lowbit_carryA = 0;
    reg lowbit_store_carryA = 0;
    wire [3:0] lowbit_store74_diffB = {1'b0, lowbit_store74_B} + {1'b0, ~lowbit74_B} + 1'b1;    
    reg lowbit_carryB = 0;
    reg lowbit_store_carryB = 0;
        
    reg [12:0] sum74_storeA = {13{1'b0}};
    wire [12:0] sum74_A = {test_carry[1], dsp_out[1]};
    wire [13:0] sum74_diffA = {1'b0,sum74_storeA} + {1'b1,~sum74_A} + lowbit_store_carryA;
    reg use_zminus1_A= 0;
    reg [12:0] sum74_storeB = {13{1'b0}};
    wire [12:0] sum74_B = {test_carry[3], dsp_out[3]};
    wire [13:0] sum74_diffB = {1'b0,sum74_storeB} + {1'b1,~sum74_B} + lowbit_store_carryB;
    reg use_zminus1_B = 0;
        
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

    wire [15:0] sq_sum74_A;
    wire [15:0] sq_sum74_B;                
    always @(posedge clk_i) begin
        lowbit_store74_A <= lowbit74_A;
        lowbit_store74_B <= lowbit74_B;
        
        lowbit_carryA <= lowbit_store74_diffA[3];
        lowbit_store_carryA <= lowbit_carryA;
        lowbit_carryB <= lowbit_store74_diffB[3];
        lowbit_store_carryB <= lowbit_carryB;
    
        sum74_storeA <= sum74_A;
        sum74_storeB <= sum74_B;
        
        use_zminus1_A <= sum74_diffA[13];
        use_zminus1_B <= sum74_diffB[13];

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
    end

    assign sq_sum30_A = { sum30_A_shreg[1], lowbit30_A_shreg[3] };
    assign sq_sum30_B = { sum30_B_shreg[1], lowbit30_B_shreg[3] };

    // now we stick everything into an SRL, and adjust the length
    // to line up based on use_undelayed_A.
    srlvec #(.NBITS(13))
        u_sum74_dlyA(.clk(clk_i),
                     .ce(1'b1),
                     .a( { 3'b000, use_zminus1_A}),
                     .din( sum74_storeA ),
                     .dout(sq_sum74_A[15:3]));
    srlvec #(.NBITS(3))
        u_lb74_dlyA(.clk(clk_i),
                    .ce(1'b1),
                    .a( { 3'b001, use_zminus1_A}),
                    .din( lowbit_store74_A ),
                    .dout(sq_sum74_A[2:0]));                     

    srlvec #(.NBITS(13))
        u_sum74_dlyB(.clk(clk_i),
                     .ce(1'b1),
                     .a( { 3'b000, use_zminus1_B}),
                     .din( sum74_storeB ),
                     .dout(sq_sum74_B[15:3]));
    srlvec #(.NBITS(3))
        u_lb74_dlyB(.clk(clk_i),
                    .ce(1'b1),
                    .a( { 3'b001, use_zminus1_B }),
                    .din( lowbit_store74_B ),
                    .dout(sq_sum74_B[2:0]));
    
    // and now FINALLY we add it up in the two24
    wire [1:0][23:0] final_dsp_out;
    two24_dsp u_dsp(.clk_i(clk_i),
                    .AB_i({ {8{1'b0}}, sq_sum30_B, {8{1'b0}}, sq_sum30_A }),
                    .C_i( { {8{1'b0}}, sq_sum74_B, {8{1'b0}}, sq_sum74_A }),
                    .P_o( final_dsp_out ));
    
    assign envelopeA_o = final_dsp_out[0][17:0];
    assign envelopeB_o = final_dsp_out[1][17:0];            
endmodule
