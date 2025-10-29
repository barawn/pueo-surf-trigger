`timescale 1ns / 1ps
// Using the 8-fold sum for the LF trigger is extremely inefficient
// since there are only 5 channels summed. Instead, we use a 5:3
// compressor plus a ternary adder, which is functionally equivalent
// to two full adders although without the carry chain out of the
// first one.
//
// The 5:3 compressor actually makes it obvious why the offset binary
// rep is helpful, because it is now actually literally smaller.
// Since we're only adding 5 things, however, the add constant
// needs to be bigger: if we were adding zero, the extra 3 would have
// a total of 48, plus 2 gives 50. This is an unsigned range of 6 bits,
// meaning that the 5:3 compressor needs to be 6 bits to let the add
// constant fit.
//
// So for instance if we add -1, -1, -1, -1, -1, we actually
// are adding 15, 15, 15, 15, 15, and 50, giving 125.
// Flipping the top bit back gives 253 or -3 signed.
// See the advantage? If we did this in signed rep, we would need
// a full 8-bit 5:3 compressor set.
module beamform_lowampa #(parameter [5:0] ADD_CONSTANT = 6'd50,
                          parameter [4:0] INVERSION = 5'b00000,
                          parameter NSAMP=4,
                          parameter NBIT=5)(
        input clk_i,
        input [NSAMP*NBIT-1:0] A,
        input [NSAMP*NBIT-1:0] B,
        input [NSAMP*NBIT-1:0] C,
        input [NSAMP*NBIT-1:0] D,
        input [NSAMP*NBIT-1:0] E,
        output [NSAMP*(NBIT+3)-1:0] O
    );

    // HOWEVER - We can't use the "stock" 5:3 compressor because we need the
    // add constant! Really, this is a 6:3 compressor, but the trick is that
    // the 6th input is ALWAYS 0 or 1 based on the add constant.
    
    // The sum of a 6:3 compressor is 
    // 64'h69969669_96696996 - if I5 is high, this is 69969669. Else 96696996.
    localparam [31:0] S63_INIT_TRUE =   32'h69969669;
    localparam [31:0] S63_INIT_FALSE =  32'h96696996;
    // Carry is 8117177E_177E7EE8
    localparam [31:0] C63_INIT_TRUE =   32'h8117177E;
    localparam [31:0] C63_INIT_FALSE=   32'h177E7EE8;
    // and ccarry is FEE8E880E8008000
    localparam [31:0] D63_INIT_TRUE =   32'hFEE8E880;
    localparam [31:0] D63_INIT_FALSE =  32'hE8008000;

    // this is so dumb
    function [31:0] lut_recalculate;
        input [31:0] initial_lut;
        input [4:0] inversion;
        reg [31:0] lut_recalc_0;
        reg [31:0] lut_recalc_1;
        reg [31:0] lut_recalc_2;
        reg [31:0] lut_recalc_3;
        begin
            if (inversion[0]) lut_recalc_0 = {initial_lut[30],
                                              initial_lut[31],
                                              initial_lut[28],
                                              initial_lut[29],
                                              initial_lut[26],
                                              initial_lut[27],
                                              initial_lut[24],
                                              initial_lut[25],
                                              initial_lut[22],
                                              initial_lut[23],
                                              initial_lut[20],
                                              initial_lut[21],
                                              initial_lut[18],
                                              initial_lut[19],
                                              initial_lut[16],
                                              initial_lut[17],
                                              initial_lut[14],
                                              initial_lut[15],
                                              initial_lut[12],
                                              initial_lut[13],
                                              initial_lut[10],
                                              initial_lut[11],
                                              initial_lut[8],
                                              initial_lut[9],
                                              initial_lut[6],
                                              initial_lut[7],
                                              initial_lut[4],
                                              initial_lut[5],
                                              initial_lut[2],
                                              initial_lut[3],
                                              initial_lut[0],
                                              initial_lut[1] };
            else lut_recalc_0 = initial_lut;
            if (inversion[1]) lut_recalc_1 = {lut_recalc_0[28 +: 2],
                                              lut_recalc_0[30 +: 2],
                                              lut_recalc_0[24 +: 2],
                                              lut_recalc_0[26 +: 2],
                                              lut_recalc_0[20 +: 2],
                                              lut_recalc_0[22 +: 2],
                                              lut_recalc_0[16 +: 2],
                                              lut_recalc_0[18 +: 2],
                                              lut_recalc_0[12 +: 2],
                                              lut_recalc_0[14 +: 2],
                                              lut_recalc_0[8 +: 2],
                                              lut_recalc_0[10 +: 2],
                                              lut_recalc_0[4 +: 2],
                                              lut_recalc_0[6 +: 2],
                                              lut_recalc_0[0 +: 2],
                                              lut_recalc_0[2 +: 2] };
            else lut_recalc_1 = lut_recalc_0;
            
            if (inversion[2]) lut_recalc_2 = {lut_recalc_1[24 +: 4],
                                              lut_recalc_1[28 +: 4],
                                              lut_recalc_1[16 +: 4],
                                              lut_recalc_1[20 +: 4],
                                              lut_recalc_1[8 +: 4],
                                              lut_recalc_1[12 +: 4],
                                              lut_recalc_1[0 +: 4],
                                              lut_recalc_1[4 +: 4] };
            else lut_recalc_2 = lut_recalc_1;
            
            if (inversion[3]) lut_recalc_3 = {lut_recalc_2[16 +: 8],
                                              lut_recalc_2[24 +: 8],
                                              lut_recalc_2[0 +: 8],
                                              lut_recalc_2[8 +: 8] };
            else lut_recalc_3 = lut_recalc_2;
            
            if (inversion[4]) lut_recalculate = { lut_recalc_3[0 +: 16],
                                                  lut_recalc_3[16 +: 16] };
            else lut_recalculate = lut_recalc_3;                                                      
        end
    endfunction        
        
    generate
        genvar s, i;
        for (s=0;s<NSAMP;s=s+1) begin : L
            // Our addends are in offset binary, but because the correction
            // add is too large, we need to extend them to 6 bits.
            wire [4:0][(NBIT+1)-1:0] addends =
                { 1'b0, E[NBIT*s +: NBIT],
                  1'b0, D[NBIT*s +: NBIT],
                  1'b0, C[NBIT*s +: NBIT],
                  1'b0, B[NBIT*s +: NBIT],
                  1'b0, A[NBIT*s +: NBIT] };
                      

            // initialize these so they sum to zero just for fun.
            wire [5:0] s_to_ff;
            reg [5:0] s_ff = {6{1'b0}};
            wire [5:0] c_to_ff;
            reg [5:0] c_ff = {6{1'b0}};
            wire [5:0] d_to_ff;
            reg [5:0] d_ff = 6'b100000;
            
            // initialize it to zero for fun
            wire [7:0] sum_addend0 = { 2'b00, s_ff };
            wire [7:0] sum_addend1 = { 1'b0, c_ff, 1'b0 };
            wire [7:0] sum_addend2 = { d_ff, 2'b00 };
            reg [7:0] final_sum = 8'h80;
            
            for (i=0;i<6;i=i+1) begin : CSA
                localparam [31:0] S63_INIT = (ADD_CONSTANT[i]) ? S63_INIT_TRUE : S63_INIT_FALSE;
                localparam [31:0] C63_INIT = (ADD_CONSTANT[i]) ? C63_INIT_TRUE : C63_INIT_FALSE;
                localparam [31:0] D63_INIT = (ADD_CONSTANT[i]) ? D63_INIT_TRUE : D63_INIT_FALSE;
                
                // However, we ALSO need to deterministically flip
                // things to absorb input inversions.
                localparam [31:0] S63 = lut_recalculate(S63_INIT, INVERSION);
                localparam [31:0] C63 = lut_recalculate(C63_INIT, INVERSION);
                localparam [31:0] D63 = lut_recalculate(D63_INIT, INVERSION);
                
                LUT6_2 #(.INIT({C63, S63}))
                    u_cs_lut(.I5(1'b1),.I4(addends[4][i]),.I3(addends[3][i]),
                             .I2(addends[2][i]),.I1(addends[1][i]),.I0(addends[0][i]),
                              .O5(s_to_ff[i]),
                              .O6(c_to_ff[i]));
                LUT5 #(.INIT(D63))
                    u_d_lut(.I4(addends[4][i]),.I3(addends[3][i]),
                             .I2(addends[2][i]),.I1(addends[1][i]),.I0(addends[0][i]),
                             .O(d_to_ff[i]));
                always @(posedge clk_i) begin
                    s_ff[i] <= s_to_ff[i];
                    c_ff[i] <= c_to_ff[i];
                    d_ff[i] <= d_to_ff[i];
                end
            end
            always @(posedge clk_i) begin : S
                final_sum <= sum_addend0 + sum_addend1 + sum_addend2;
            end
            assign O[(NBIT+3)*s +: (NBIT+3)] = final_sum;
        end            
    endgenerate
endmodule
