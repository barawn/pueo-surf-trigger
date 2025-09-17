`timescale 1ns / 1ps    
// Second version of the 2 beam module. This version separates out
// EVERYTHING except the beamform and square.
//
// Note that there's no reason for this to be dual anymore, but
// it's there to match the others.
//
// outA_o/outB_o are just there for debugging - if needed we could
// throw them into an ILA or something.
module dual_pueo_beamform_lowampa_v2
                      #(parameter INTYPE = "RAW",
                        // thank you, SystemVerilog 2009
                        localparam NBITS=5,
                        localparam NSAMP=4,
                        localparam NCHAN=8,
                        localparam INBITS = (INTYPE == "RAW") ? NCHAN*NSAMP*NBITS : 3*NSAMP*(NBITS+2),
                        localparam OUTBITS=14
                        ) (
        input clk_i,
        input [INBITS-1:0] beamA_i,
        input [NCHAN-1:0] beamA_use,
        input [NCHAN-1:0] beamA_invert,
        input [INBITS-1:0] beamB_i,
        input [NCHAN-1:0] beamB_use,
        input [NCHAN-1:0] beamB_invert,

        output [4*NSAMP*(NBITS+3)-1:0] outA_o,
        output [NSAMP*(NBITS+3)-1:0] outB_o,

        output [NSAMP*OUTBITS-1:0] sq_outA_o,
        output [NSAMP*OUTBITS-1:0] sq_outB_o
    );
     
    // create the beams.
    wire [NBITS+2:0] beamA[NSAMP-1:0];
    wire [NBITS+2:0] beamB[NSAMP-1:0];
    // converted back to signed
    wire [NBITS+2:0] beamA_signed[NSAMP-1:0];
    wire [NBITS+2:0] beamB_signed[NSAMP-1:0];
    // actual square
    wire [13:0] beamA_sq[NSAMP-1:0];
    wire [13:0] beamB_sq[NSAMP-1:0];            
    // square output
    wire [14:0] beamA_sqout[NSAMP-1:0];
    wire [14:0] beamB_sqout[NSAMP-1:0];

    // Registers for pipelining
    reg [NCHAN*NSAMP*NBITS-1:0] beamA_i_reg = {NCHAN*NSAMP*NBITS{1'b0}};
    reg [NCHAN*NSAMP*NBITS-1:0] beamB_i_reg = {NCHAN*NSAMP*NBITS{1'b0}};
    // vectorize inputs
    wire [NBITS-1:0] beamA_vec[NCHAN-1:0][NSAMP-1:0];
    wire [NBITS-1:0] beamB_vec[NCHAN-1:0][NSAMP-1:0];

    generate
        genvar ii,jj,kk;
        if (INTYPE == "RAW") begin : RAWIN            
            always @(posedge clk_i) begin : RR
                beamA_i_reg <= beamA_i;
                beamB_i_reg <= beamB_i;
            end
        end
        // sample loop is the outer b/c once we beamform the channels disappear
        for (jj=0;jj<NSAMP;jj=jj+1) begin : SV
            // We have 2 separate input types: either we're given the raw inputs (8 channels, 8 samples, 5 bits each)
            // or a selection of postadder inputs (3 adders, 8 samples, 7 bits each).
            // The postadder input version fixes Vivado's lack of resource sharing detection.
            if (INTYPE == "RAW") begin : RAWIN
                wire [NBITS+1:0] zero = {NBITS+2{1'b0}};
            
                for (ii=0;ii<NCHAN;ii=ii+1) begin : CV
                    // channels jump by NSAMP*NBITS. also flip to offset binary
                    assign beamA_vec[ii][jj] = beamA_i_reg[NBITS*NSAMP*ii + NBITS*jj +: NBITS]; //L Changed from Patrick's version
                    assign beamB_vec[ii][jj] = beamB_i_reg[NBITS*NSAMP*ii + NBITS*jj +: NBITS];
                end
    
                // First beamforming step is to sum at each (variously delayed) 3 GHz clock tick
    
                // beamform A
                fivebit_8way_ternary #(.ADD_CONSTANT(5'd2)) // The constant add is to correct for the -0.5 in symmetric rep
                    u_beamA(.clk_i(clk_i),
                        .A(beamA_use[1]?((beamA_invert[1])?(~beamA_vec[1][jj]):(beamA_vec[1][jj])):(5'b10000)),
                        .B(beamA_use[2]?((beamA_invert[2])?(~beamA_vec[2][jj]):(beamA_vec[2][jj])):(5'b10000)),
                        .C(beamA_use[3]?((beamA_invert[3])?(~beamA_vec[3][jj]):(beamA_vec[3][jj])):(5'b10000)),
                        .D(beamA_use[5]?((beamA_invert[5])?(~beamA_vec[5][jj]):(beamA_vec[5][jj])):(5'b10000)),
                        .E(beamA_use[6]?((beamA_invert[6])?(~beamA_vec[6][jj]):(beamA_vec[6][jj])):(5'b10000)),
                        .F(beamA_use[7]?((beamA_invert[7])?(~beamA_vec[7][jj]):(beamA_vec[7][jj])):(5'b10000)),
                        .G(beamA_use[0]?((beamA_invert[0])?(~beamA_vec[0][jj]):(beamA_vec[0][jj])):(5'b10000)),
                        .H(beamA_use[4]?((beamA_invert[4])?(~beamA_vec[4][jj]):(beamA_vec[4][jj])):(5'b10000)),
                            .O(beamA[jj])); // Sum of the delayed beams for each (phase offset) sample
                assign outA_o[(32)*jj +: (32)] = {{4{beamA_vec[6][jj][4]}},~beamA_vec[6][jj][3:0],{4{~beamA_vec[4][jj][4]}},beamA_vec[4][jj][3:0],{4{~beamA_vec[2][jj][4]}},beamA_vec[2][jj][3:0],{4{~beamA_vec[0][jj][4]}},beamA_vec[0][jj][3:0]};
                // beamform B
                fivebit_8way_ternary #(.ADD_CONSTANT(5'd2)) // The constant add is to correct for the -0.5 in symmetric rep
                    u_beamB(.clk_i(clk_i),
                        .A(beamB_use[1]?(beamB_invert[1]?(~beamB_vec[1][jj]):(beamB_vec[1][jj])):(5'b10000)),
                        .B(beamB_use[2]?(beamB_invert[2]?(~beamB_vec[2][jj]):(beamB_vec[2][jj])):(5'b10000)),
                        .C(beamB_use[3]?(beamB_invert[3]?(~beamB_vec[3][jj]):(beamB_vec[3][jj])):(5'b10000)),
                        .D(beamB_use[5]?(beamB_invert[5]?(~beamB_vec[5][jj]):(beamB_vec[5][jj])):(5'b10000)),
                        .E(beamB_use[6]?(beamB_invert[6]?(~beamB_vec[6][jj]):(beamB_vec[6][jj])):(5'b10000)),
                        .F(beamB_use[7]?(beamB_invert[7]?(~beamB_vec[7][jj]):(beamB_vec[7][jj])):(5'b10000)),
                        .G(beamB_use[0]?(beamB_invert[0]?(~beamB_vec[0][jj]):(beamB_vec[0][jj])):(5'b10000)),
                        .H(beamB_use[4]?(beamB_invert[4]?(~beamB_vec[4][jj]):(beamB_vec[4][jj])):(5'b10000)),
                            .O(beamB[jj])); // Sum of the delayed beams for each (phase offset) sample
            end else begin : PAIN
                // The postadd version doesn't need pipeline regs.
                wire [2:0][(NBITS+2)-1:0] A_stage1 = beamA_i;
                wire [2:0][(NBITS+2)-1:0] B_stage1 = beamB_i;
                
                ternary_add_sub_prim #(.input_word_size(NBITS+2),
                                       .is_signed(1'b0))
                    u_stage2A(.clk_i(clk_i),
                              .rst_i(1'b0),
                              .x_i(A_stage1[0]),
                              .y_i(A_stage1[1]),
                              .z_i(A_stage1[2]),
                              .sum_o( beamA[jj] ));
                ternary_add_sub_prim #(.input_word_size(NBITS+2),
                                       .is_signed(1'b0))
                    u_stage2B(.clk_i(clk_i),
                              .rst_i(1'b0),
                              .x_i(B_stage1[0]),
                              .y_i(B_stage1[1]),
                              .z_i(B_stage1[2]),
                              .sum_o( beamB[jj] ));                                                                     
            end
            
            // And then everything else after that is common.
            
            // Flip the top bit, reverting from offset binary to two's complement.
            assign beamA_signed[jj] = {!beamA[jj][NBITS+2], beamA[jj][NBITS+1:0]};
            assign beamB_signed[jj] = {!beamB[jj][NBITS+2], beamB[jj][NBITS+1:0]};

            // Square the now summed values for each 3 GHz clock tick
            signed_8b_square u_squarerA(
                .clk_i(clk_i),
                .in_i(beamA_signed[jj]),    // [7:0] 
                .out_o(beamA_sqout[jj])); // [14:0] , although the top (15th) bit will never be set for our symmetric representation value range, so drop it
            assign beamA_sq[jj] = beamA_sqout[jj][13:0]; // slicing off top bit

            signed_8b_square u_squarerB(
                .clk_i(clk_i),
                .in_i(beamB_signed[jj]),    // [7:0] 
                .out_o(beamB_sqout[jj])); // [14:0] , although the top (15th) bit will never be set for our symmetric representation value range, so drop it
            assign beamB_sq[jj] = beamB_sqout[jj][13:0]; // slicing off top bit

            //assign outA_o[(NBITS+3)*jj +: (NBITS+3)] = beamA_signed[jj];
            assign outB_o[(NBITS+3)*jj +: (NBITS+3)] = beamB_signed[jj];

            //actually (signed-.5)^2 = signed^2 - signed +.25 add back in signed value to re-center
            assign sq_outA_o[OUTBITS*jj +: OUTBITS] = beamA_sqout[jj];//+{{(OUTBITS-NBITS-3){beamA_signed[jj][NBITS+2]}}, beamA_signed[jj][NBITS+2:0]};
            assign sq_outB_o[OUTBITS*jj +: OUTBITS] = beamB_sqout[jj];//+{{(OUTBITS-NBITS-3){beamB_signed[jj][NBITS+2]}}, beamB_signed[jj][NBITS+2:0]};
        end        
    endgenerate
    
endmodule
