`timescale 1ns / 1ps    
// Second version of the 2 beam module. This version separates out
// EVERYTHING except the beamform and square.
//
// Note that there's no reason for this to be dual anymore, but
// it's there to match the others.
//
// outA_o/outB_o are just there for debugging - if needed we could
// throw them into an ILA or something.
module dual_pueo_beamform_v2
                      #(parameter INTYPE = "RAW",
                        // thank you, SystemVerilog 2009
                        localparam NBITS=5,
                        localparam NSAMP=8,
                        localparam NCHAN=8,
                        localparam INBITS = (INTYPE == "RAW") ? NCHAN*NSAMP*NBITS : 3*NSAMP*(NBITS+2),
                        localparam OUTBITS=14
                        ) (
        input clk_i,
        input [INBITS-1:0] beamA_i,
        input [INBITS-1:0] beamB_i,

        output [NSAMP*(NBITS+3)-1:0] outA_o,
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
                fivebit_8way_ternary #(.ADD_CONSTANT(5'd4)) // The constant add is to correct for the -0.5 in symmetric rep
                    u_beamA(.clk_i(clk_i),
                            .A(beamA_vec[0][jj]),
                            .B(beamA_vec[1][jj]),
                            .C(beamA_vec[2][jj]),
                            .D(beamA_vec[3][jj]),
                            .E(beamA_vec[4][jj]),
                            .F(beamA_vec[5][jj]),
                            .G(beamA_vec[6][jj]),
                            .H(beamA_vec[7][jj]),
                            .O(beamA[jj])); // Sum of the delayed beams for each (phase offset) sample
                // beamform B
                fivebit_8way_ternary #(.ADD_CONSTANT(5'd4)) // The constant add is to correct for the -0.5 in symmetric rep
                    u_beamB(.clk_i(clk_i),
                            .A(beamB_vec[0][jj]),
                            .B(beamB_vec[1][jj]),
                            .C(beamB_vec[2][jj]),
                            .D(beamB_vec[3][jj]),
                            .E(beamB_vec[4][jj]),
                            .F(beamB_vec[5][jj]),
                            .G(beamB_vec[6][jj]),
                            .H(beamB_vec[7][jj]),
                            .O(beamB[jj])); // Sum of the delayed beams for each (phase offset) sample
            end else begin : PAIN
                // The postadd version doesn't need pipeline regs.
                localparam ADDER0_BASE = (NBITS+2)*jj;
                localparam ADDER1_BASE = (NBITS+2)*NSAMP + (NBITS+2)*jj;
                localparam ADDER2_BASE = 2*(NBITS+2)*NSAMP + (NBITS+2)*jj;
                
                // To grab the inputs
                wire [(NBITS+2)-1:0] A_adder0 = beamA_i[ADDER0_BASE +: (NBITS+2)];
                wire [(NBITS+2)-1:0] A_adder1 = beamA_i[ADDER1_BASE +: (NBITS+2)];
                wire [(NBITS+2)-1:0] A_adder2 = beamA_i[ADDER2_BASE +: (NBITS+2)];

                wire [(NBITS+2)-1:0] B_adder0 = beamB_i[ADDER0_BASE +: (NBITS+2)];
                wire [(NBITS+2)-1:0] B_adder1 = beamB_i[ADDER1_BASE +: (NBITS+2)];
                wire [(NBITS+2)-1:0] B_adder2 = beamB_i[ADDER2_BASE +: (NBITS+2)];
                
                ternary_add_sub_prim #(.input_word_size(NBITS+2),
                                       .is_signed(1'b0))
                    u_stage2A(.clk_i(clk_i),
                              .rst_i(1'b0),
                              .x_i(A_adder0),
                              .y_i(A_adder1),
                              .z_i(A_adder2),
                              .sum_o( beamA[jj] ));
                ternary_add_sub_prim #(.input_word_size(NBITS+2),
                                       .is_signed(1'b0))
                    u_stage2B(.clk_i(clk_i),
                              .rst_i(1'b0),
                              .x_i(B_adder0),
                              .y_i(B_adder1),
                              .z_i(B_adder2),
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

            assign outA_o[(NBITS+3)*jj +: (NBITS+3)] = beamA_signed[jj];
            assign outB_o[(NBITS+3)*jj +: (NBITS+3)] = beamB_signed[jj];

            assign sq_outA_o[OUTBITS*jj +: OUTBITS] = beamA_sqout[jj];
            assign sq_outB_o[OUTBITS*jj +: OUTBITS] = beamB_sqout[jj];
        end        
    endgenerate
    
endmodule
