`timescale 1ns / 1ps
// Second version of a Shannon-Whitaker LP filter.
//
// This version ensures that all DSPs have at least a preadd or multiplier
// register in their path, which should guarantee timing even when the
// FPGA becomes extremely full.
module lowampa_matched_filter_v2 #(parameter NBITS=12,
                                    parameter NSAMPS=4,
                                    parameter OUTQ_INT=12,
                                    parameter OUTQ_FRAC=0)(
        input clk_i,
        input [NBITS*NSAMPS-1:0] in_i,
        output [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] out_o
    );
    
    // for ease of use
    wire [NBITS-1:0] xin[NSAMPS-1:0];
    generate
        genvar ii,jj;
        for (ii=0;ii<NSAMPS;ii=ii+1) begin : S
            for (jj=0;jj<NBITS;jj=jj+1) begin : B
                assign xin[ii][jj] = in_i[NBITS*ii + jj];
            end
        end
    endgenerate   

   //localparam taps = [1,1,1,1,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,1,1,1,1,1,1,1,1,0,0,-1,-1,-2,-2,-2,-2,-1,0,0,1,2,2,2,2,2,1,0,-1,-2,-2,-2,-2,-2,-1,1,2,2,4,2,2,0,-2,-4,-4,-2,0,2,4,4,2,-1,-2,-4,-1,4,4,-1,-4,0,1]
   localparam negative_taps = 32; //
   localparam delayed_store_size = 20;
   reg [NBITS-1:0] delayed_inputs [delayed_store_size-5:0];
   wire [NBITS-1:0] delay_x_array [delayed_store_size-1:0];
   assign delay_x_array[0] = xin[3];
   assign delay_x_array[1] = xin[2];
   assign delay_x_array[2] = xin[1];
   assign delay_x_array[3] = xin[0];


   //copy input data delayed 4 spaces along
   generate
     genvar j;
     for (j=0;j<delayed_store_size-4;j=j+1)
       begin
	 assign delay_x_array[j+4] = delayed_inputs[j];
	 always @(posedge clk_i)
	 begin
	   delayed_inputs[j] <=delay_x_array[j];
	 end
       end
   endgenerate

    // Convert between fixed point representations (this only works to EXPAND, not COMPRESS)
    // n.b. I should convert this into a function: the macro version apparently causes problems when passed with parameters.
    // Who knows, Xilinx weirdness.
//    `define QCONV( inval , SRC_QINT, SRC_QFRAC, DST_QINT, DST_QFRAC )   \
//        ( { {( DST_QINT - SRC_QINT ) { inval[ (SRC_QINT+SRC_QFRAC) - 1 ] }}, inval, { ( DST_QFRAC - SRC_QFRAC ) {1'b0} } } )


    // We generate 2 delayed inputs.
    wire [47:0] sample_out[NSAMPS-1:0];
    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : filter
   wire [47:0] d19_to_d18;
   wire [47:0] d18_to_d17;
   wire [47:0] d17_to_d16;
   wire [47:0] d16_to_d15;
   wire [47:0] d15_to_d14;
   wire [47:0] d14_to_d13;
   wire [47:0] d13_to_d12;
   wire [47:0] d12_to_d11;
   wire [47:0] d11_to_d10;
   wire [47:0] d10_to_d9;
   wire [47:0] d9_to_d8;
   wire [47:0] d8_to_d7;
   wire [47:0] d7_to_d6;
   wire [47:0] d6_to_d5;
   wire [47:0] d5_to_d4;
   wire [47:0] d4_to_d3;
   wire [47:0] d3_to_d2;
   wire [47:0] d2_to_d1;
   wire [47:0] d1_to_d0;
   wire [47:0] d0_to_dN1;
   wire [47:0] dN1_to_dN2;
                lowampa_match_dsp #(.ADD_PCIN("FALSE"))
                         taps_d19(.clk_i(clk_i),
                                 .a_i({26'b0}),//out of taps
                                 .d_i(negative_taps),//every negative via ~ subtracts 1, compensate by adding 1 for each
				 //to return to 2's complement
				 .c_i({{36{delay_x_array[79+i-76][11]}},delay_x_array[79+i-76]}),//79=1
				 .b_i(18'b1),
				 .pcout_o( d19_to_d18));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d18(.clk_i(clk_i),
				 //78 are 0
                                 .a_i(~{{12{delay_x_array[77+i-72][11]}},delay_x_array[77+i-72],2'b0}),//77=-4
                                 .d_i(~{{14{delay_x_array[76+i-72][11]}},delay_x_array[76+i-72]}),//76=-1
                                 .c_i({{34{delay_x_array[75+i-72][11]}},delay_x_array[75+i-72],2'b0}),//75=4
				 .b_i(18'b1),
                                 .pcin_i( d19_to_d18 ),
				 .pcout_o( d18_to_d17));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d17(.clk_i(clk_i),
                                 .a_i({{12{delay_x_array[74+i-68][11]}},delay_x_array[74+i-68],2'b0}),//74=4
                                 .d_i(~{{14{delay_x_array[73+i-68][11]}},delay_x_array[73+i-68]}),//73=-1
                                 .c_i(~{{34{delay_x_array[72+i-68][11]}},delay_x_array[72+i-68],2'b0}),//72=-4
				 .b_i(18'b1),
                                 .pcin_i( d18_to_d17 ),
				 .pcout_o( d17_to_d16));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d16(.clk_i(clk_i),
                                 .a_i(~{{13{delay_x_array[71+i-64][11]}},delay_x_array[71+i-64],1'b0}),//71=-2
                                 .d_i(~{{14{delay_x_array[70+i-64][11]}},delay_x_array[70+i-64]}),//70=-1
                                 .c_i({{35{delay_x_array[69+i-64][11]}},delay_x_array[69+i-64],1'b0}),//69=2
				 .b_i(18'b1),
                                 .pcin_i( d17_to_d16 ),
				 .pcout_o( d16_to_d15));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d15(.clk_i(clk_i),
                                 .a_i({{12{delay_x_array[68+i-60][11]}},delay_x_array[68+i-60],2'b0}),//68=4
                                 .d_i({{12{delay_x_array[67+i-60][11]}},delay_x_array[67+i-60],2'b0}),//67=4
                                 .c_i({{35{delay_x_array[66+i-60][11]}},delay_x_array[66+i-60],1'b0}),//66=2
				 .b_i(18'b1),
                                 .pcin_i( d16_to_d15 ),
				 .pcout_o( d15_to_d14));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d14(.clk_i(clk_i),
				 //65 is 0
                                 .a_i(~{{13{delay_x_array[64+i-56][11]}},delay_x_array[64+i-56],1'b0}),//64=-2
                                 .d_i(~{{12{delay_x_array[63+i-56][11]}},delay_x_array[63+i-56],2'b0}),//63=-4
                                 .c_i(~{{34{delay_x_array[62+i-56][11]}},delay_x_array[62+i-56],2'b0}),//62=-4
				 .b_i(18'b1),
                                 .pcin_i( d15_to_d14 ),
				 .pcout_o( d14_to_d13));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d13(.clk_i(clk_i),
                                 .a_i(~{{13{delay_x_array[61+i-52][11]}},delay_x_array[61+i-52],1'b0}),//61=-2
				 //60 is 0
                                 .d_i({{13{delay_x_array[59+i-52][11]}},delay_x_array[59+i-52],1'b0}),//59=2
                                 .c_i({{35{delay_x_array[58+i-52][11]}},delay_x_array[58+i-52],1'b0}),//58=2
				 .b_i(18'b1),
                                 .pcin_i( d14_to_d13 ),
				 .pcout_o( d13_to_d12));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d12(.clk_i(clk_i),
                                 .a_i({{12{delay_x_array[57+i-48][11]}},delay_x_array[57+i-48],2'b0}),//57=4
                                 .d_i({{13{delay_x_array[56+i-48][11]}},delay_x_array[56+i-48],1'b0}),//56=2
                                 .c_i({{35{delay_x_array[55+i-48][11]}},delay_x_array[55+i-48],1'b0}),//55=2
				 .b_i(18'b1),
                                 .pcin_i( d13_to_d12 ),
				 .pcout_o( d12_to_d11));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d11(.clk_i(clk_i),
                                 .a_i({{14{delay_x_array[54+i-44][11]}},delay_x_array[54+i-44]}),//54=1
                                 .d_i(~{{14{delay_x_array[53+i-44][11]}},delay_x_array[53+i-44]}),//53=-1
                                 .c_i(~{{35{delay_x_array[52+i-44][11]}},delay_x_array[52+i-44],1'b0}),//52=-2
				 .b_i(18'b1),
                                 .pcin_i( d12_to_d11 ),
				 .pcout_o( d11_to_d10));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d10(.clk_i(clk_i),
                                 .a_i(~{{13{delay_x_array[51+i-40][11]}},delay_x_array[51+i-40],1'b0}),//51=-2
                                 .d_i(~{{13{delay_x_array[50+i-40][11]}},delay_x_array[50+i-40],1'b0}),//50=-2
                                 .c_i(~{{35{delay_x_array[49+i-40][11]}},delay_x_array[49+i-40],1'b0}),//49=-2
				 .b_i(18'b1),
                                 .pcin_i( d11_to_d10 ),
				 .pcout_o( d10_to_d9));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d09(.clk_i(clk_i),
                                 .a_i(~{{13{delay_x_array[48+i-36][11]}},delay_x_array[48+i-36],1'b0}),//48=-2
                                 .d_i(~{{14{delay_x_array[47+i-36][11]}},delay_x_array[47+i-36]}),//47=-1
				 //46 is 0
                                 .c_i({{36{delay_x_array[45+i-36][11]}},delay_x_array[45+i-36]}),//45=1
				 .b_i(18'b1),
                                 .pcin_i( d10_to_d9 ),
				 .pcout_o( d9_to_d8));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d08(.clk_i(clk_i),
                                 .a_i({{13{delay_x_array[44+i-32][11]}},delay_x_array[44+i-32],1'b0}),//44=2
                                 .d_i({{13{delay_x_array[43+i-32][11]}},delay_x_array[43+i-32],1'b0}),//43=2
                                 .c_i({{35{delay_x_array[42+i-32][11]}},delay_x_array[42+i-32],1'b0}),//42=2
				 .b_i(18'b1),
                                 .pcin_i( d9_to_d8 ),
				 .pcout_o( d8_to_d7));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d07(.clk_i(clk_i),
                                 .a_i({{13{delay_x_array[41+i-28][11]}},delay_x_array[41+i-28],1'b0}),//41=2
                                 .d_i({{13{delay_x_array[40+i-28][11]}},delay_x_array[40+i-28],1'b0}),//40=2
                                 .c_i({{36{delay_x_array[39+i-28][11]}},delay_x_array[39+i-28]}),//39=1
				 .b_i(18'b1),
                                 .pcin_i( d8_to_d7 ),
				 .pcout_o( d7_to_d6));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d06(.clk_i(clk_i),
				 //38-37 are 0
                                 .a_i(~{{14{delay_x_array[36+i-24][11]}},delay_x_array[36+i-24]}),//36=-1
                                 .d_i(~{{13{delay_x_array[35+i-24][11]}},delay_x_array[35+i-24],1'b0}),//35=-2
                                 .c_i(~{{35{delay_x_array[34+i-24][11]}},delay_x_array[34+i-24],1'b0}),//34=-2
				 .b_i(18'b1),
                                 .pcin_i( d7_to_d6 ),
				 .pcout_o( d6_to_d5));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d05(.clk_i(clk_i),
                                 .a_i(~{{13{delay_x_array[33+i-20][11]}},delay_x_array[33+i-20],1'b0}),//33=-2
                                 .d_i(~{{13{delay_x_array[32+i-20][11]}},delay_x_array[32+i-20],1'b0}),//32=-2
                                 .c_i(~{{36{delay_x_array[31+i-20][11]}},delay_x_array[31+i-20]}),//31=-1
				 .b_i(18'b1),
                                 .pcin_i( d6_to_d5 ),
				 .pcout_o( d5_to_d4));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d04(.clk_i(clk_i),
                                 .a_i(~{{14{delay_x_array[30+i-16][11]}},delay_x_array[30+i-16]}),//30=-1
				 //29-28 are 0
                                 .d_i({{14{delay_x_array[27+i-16][11]}},delay_x_array[27+i-16]}),//27=1
                                 .c_i({{36{delay_x_array[26+i-16][11]}},delay_x_array[26+i-16]}),//26=1
				 .b_i(18'b1),
                                 .pcin_i( d5_to_d4 ),
				 .pcout_o( d4_to_d3));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d03(.clk_i(clk_i),
                                 .a_i({{14{delay_x_array[25+i-12][11]}},delay_x_array[25+i-12]}),//25=1
                                 .d_i({{14{delay_x_array[24+i-12][11]}},delay_x_array[24+i-12]}),//24=1
                                 .c_i({{36{delay_x_array[23+i-12][11]}},delay_x_array[23+i-12]}),//23=1
				 .b_i(18'b1),
                                 .pcin_i( d4_to_d3 ),
				 .pcout_o( d3_to_d2));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d02(.clk_i(clk_i),
                                 .a_i({{14{delay_x_array[22+i-8][11]}},delay_x_array[22+i-8]}),//22=1
                                 .d_i({{14{delay_x_array[21+i-8][11]}},delay_x_array[21+i-8]}),//21=1
                                 .c_i({{36{delay_x_array[20+i-8][11]}},delay_x_array[20+i-8]}),//20=1
				 .b_i(18'b1),
                                 .pcin_i( d3_to_d2 ),
				 .pcout_o( d2_to_d1));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d01(.clk_i(clk_i),
				 //19-17 are 0
                                 .a_i(~{{14{delay_x_array[16+i-4][11]}},delay_x_array[16+i-4]}),//16=-1
                                 .d_i(~{{14{delay_x_array[15+i-4][11]}},delay_x_array[15+i-4]}),//15=-1
                                 .c_i(~{{36{delay_x_array[14+i-4][11]}},delay_x_array[14+i-4]}),//14=-1
				 .b_i(18'b1),
                                 .pcin_i( d2_to_d1 ),
				 .pcout_o( d1_to_d0));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_d00(.clk_i(clk_i),
                                 .a_i(~{{14{delay_x_array[13+i+0][11]}},delay_x_array[13+i+0]}),//13=-1
                                 .d_i(~{{14{delay_x_array[12+i+0][11]}},delay_x_array[12+i+0]}),//12=-1
                                 .c_i(~{{36{delay_x_array[11+i+0][11]}},delay_x_array[11+i+0]}),//11=-1
				 .b_i(18'b1),
                                 .pcin_i( d1_to_d0 ),
				 .pcout_o( d0_to_dN1));
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_dN1(.clk_i(clk_i),
                                 .a_i(~{{14{delay_x_array[10+i+4][11]}},delay_x_array[10+i+4]}),//10=-1
                                 .d_i(~{{14{delay_x_array[9+i+4][11]}},delay_x_array[9+i+4]}),//9=-1
				 //8-4 are 0
                                 .c_i({{36{delay_x_array[3+i+4][11]}},delay_x_array[3+i+4]}),//3=1
				 .b_i(18'b1),
                                 .pcin_i( d0_to_dN1 ),
				 .pcout_o( dN1_to_dN2)); 
                lowampa_match_dsp #(.ADD_PCIN("TRUE"))
                         taps_dN2(.clk_i(clk_i),
                                 .a_i({{14{delay_x_array[2+i+8][11]}},delay_x_array[2+i+8]}),//2=1
                                 .d_i({{14{delay_x_array[1+i+8][11]}},delay_x_array[1+i+8]}),//1=1
                                 .c_i({{36{delay_x_array[0+i+8][11]}},delay_x_array[0+i+8]}),//0=1
				 .b_i(18'b1),
                                 .pcin_i( dN1_to_dN2 ),
                                 .p_o(sample_out[i]));                                            
            //divide by 16
            assign out_o[(OUTQ_INT+OUTQ_FRAC)*i +: (OUTQ_INT+OUTQ_FRAC)] = sample_out[NSAMPS-i-1][4 +: (OUTQ_INT)];
        end
    endgenerate
    
    
endmodule
