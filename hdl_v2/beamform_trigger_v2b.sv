`timescale 1ns / 1ps
// V2B now uses the structure where you declare sub-beams (made out of triplets or doublets of antennas)
// first, and then full beams out of 2 triplets and (optionally) a doublet.
//
// Reuses a lot of machinery from the previous one, but restructured.

// If FULL = FALSE, we use the dummys.
// Dummy beam 0 is "no delays straight through."
// Dummy beam 1 is el = -2.612 az = 1.117

`define TRIPLET_DUMMY_TOTAL 4
`define DOUBLET_DUMMY_TOTAL 2
`define TRIPLET_DUMMY_DELAYS    '{  '{0,0,0},       \
                                    '{0,0,0},       \
                                    '{11,11,11},    \
                                    '{12,12,12} }

// these move into a header eventually
`define TRIPLET_DUMMY_INDICES   '{  '{1,2,3},       \
                                    '{5,6,7},       \
                                    '{1,2,3},       \
                                    '{5,6,7} }

`define DOUBLET_DUMMY_DELAYS    '{  '{0,0},         \
                                    '{0,2} }

`define BEAM_CONTENTS_DUMMY     '{  '{0,1,0},       \
                                    '{2,3,1} }

`include "optimized_beams.vh"

//`define TRIPLET_ADDER_TOTAL 3
//`define TRIPLET_ADDER_DELAYS    '{  '{4,2,0},       \
//                                    '{4,2,0},       \
//                                    '{5,3,1} }
//`define TRIPLET_ADDER_INDICES   '{  '{1,2,3},       \
//                                    '{5,6,7},       \
//                                    '{5,6,7} }

//`define DOUBLET_ADDER_TOTAL 2
//`define DOUBLET_ADDER_DELAYS '{ '{1,4},     \
//                                '{0,3} }

//`define NUM_BEAM 2
//`define BEAM_CONTENTS '{ '{0,1,0},          \
//                         '{0,2,1} }

module beamform_trigger_v2b #(parameter FULL = "TRUE",
                              parameter DEBUG = "FALSE",
                              localparam NBEAMS = (FULL == "TRUE") ? `NUM_BEAM : 2,
                              localparam NBITS=5,
                              localparam NSAMP=8,
                              localparam NCHAN=8)(
        input clk_i,
        input [NCHAN-1:0][NSAMP*NBITS-1:0] data_i,
        input [18*2-1:0] thresh_i,
        input [1:0] thresh_wr_i,
        input [1:0] thresh_update_i,
        output [2*NBEAMS-1:0] trigger_o
    );

    localparam SB_BITS = 7;
    localparam SAMPLE_STORE_DEPTH = 8+2;
    
    // Triplets need indices, they move a bit.
    localparam int triplet_delay_full [0:(`TRIPLET_ADDER_TOTAL)-1][0:2] = `TRIPLET_ADDER_DELAYS;
    localparam int triplet_index_full [0:(`TRIPLET_ADDER_TOTAL)-1][0:2] = `TRIPLET_ADDER_INDICES;
    // Doublets do not have indices, they are always A/E (top antennas)
    localparam int doublet_delay_full [0:(`DOUBLET_ADDER_TOTAL)-1][0:1] = `DOUBLET_ADDER_DELAYS;

    // Beams are constructed from 2 triplets and optionally a doublet. If the doublet index is
    // 255 (really greater than DOUBLET_ADDER_TOTAL) this indicates no doublet.
    localparam int beam_contents_full [0:`NUM_BEAM-1][0:2] = `BEAM_CONTENTS;

    // Triplets need indices, they move a bit.
    localparam int triplet_delay_dummy [0:(`TRIPLET_DUMMY_TOTAL)-1][0:2] = `TRIPLET_DUMMY_DELAYS;
    localparam int triplet_index_dummy [0:(`TRIPLET_DUMMY_TOTAL)-1][0:2] = `TRIPLET_DUMMY_INDICES;
    // Doublets do not have indices, they are always A/E (top antennas)
    localparam int doublet_delay_dummy [0:(`DOUBLET_DUMMY_TOTAL)-1][0:1] = `DOUBLET_DUMMY_DELAYS;

    // Beams are constructed from 2 triplets and optionally a doublet. If the doublet index is
    // 255 (really greater than DOUBLET_ADDER_TOTAL) this indicates no doublet.
    localparam int beam_contents_dummy [0:1][0:2] = `BEAM_CONTENTS_DUMMY;

    localparam NTRIPLETS = (FULL == "TRUE") ? `TRIPLET_ADDER_TOTAL : `TRIPLET_DUMMY_TOTAL;
    localparam NDOUBLETS = (FULL == "TRUE") ? `DOUBLET_ADDER_TOTAL : `DOUBLET_DUMMY_TOTAL;
    
//    localparam int triplet_delay [0:NTRIPLETS-1][0:2] = (FULL == "TRUE") ? triplet_delay_full :
//                                                                           triplet_delay_dummy;
//    localparam int triplet_index [0:NTRIPLETS-1][0:2] = (FULL == "TRUE") ? triplet_index_full :
//                                                                           triplet_index_dummy;
//    localparam int doublet_delay [0:NDOUBLETS-1][0:1] = (FULL == "TRUE") ? doublet_delay_full :
//                                                                           doublet_delay_dummy;
//    localparam int beam_contents [0:NBEAMS-1][0:2] = (FULL == "TRUE") ? beam_contents_full :
//                                                                        beam_contents_dummy;

    // Sample storage array.    
    wire [SAMPLE_STORE_DEPTH*NSAMP*NBITS-1:0] sample_store[NCHAN-1:0];
    wire [2:0][NSAMP*NBITS-1:0] triplets_delayed[NTRIPLETS-1:0];
    wire [1:0][NSAMP*NBITS-1:0] doublets_delayed[NDOUBLETS-1:0];

    wire [NSAMP*SB_BITS-1:0] triplets[NTRIPLETS-1:0];
    // doublets[DOUBLET_ADDER_TOTAL] is the empty doublet
    wire [NSAMP*7-1:0] doublets[NDOUBLETS:0];

    // this is stupid, only half get connected, but whatever
    wire [47:0] cascade[NBEAMS-1:0];

//    localparam int triplet_delay [0:NTRIPLETS-1][0:2] = (FULL == "TRUE") ? triplet_delay_full :
//                                                                           triplet_delay_dummy;
//    localparam int triplet_index [0:NTRIPLETS-1][0:2] = (FULL == "TRUE") ? triplet_index_full :
//                                                                           triplet_index_dummy;
//    localparam int doublet_delay [0:NDOUBLETS-1][0:1] = (FULL == "TRUE") ? doublet_delay_full :
//                                                                           doublet_delay_dummy;
//    localparam int beam_contents [0:NBEAMS-1][0:2] = (FULL == "TRUE") ? beam_contents_full :
//                                                                        beam_contents_dummy;    
    generate
        genvar t, t_ch, t_s, d, d_ch, d_s, chan_idx, clock_idx;
        genvar b;        
        for (b=0;b<NBEAMS;b=b+2) begin : B
            localparam int beam_content[0:2] = (FULL == "TRUE") ? beam_contents_full[b] :
                                                                  beam_contents_dummy[b];
            int doublet_idx = 
                (beam_content[2] >= NDOUBLETS) ? NDOUBLETS :
                                                 beam_content[2];
            wire [NSAMP*SB_BITS-1:0] tripletA0 = triplets[beam_content[0]];
            wire [NSAMP*SB_BITS-1:0] tripletB0 = triplets[beam_content[1]];            
            wire [NSAMP*SB_BITS-1:0] doublet0 = doublets[doublet_idx];
            
            wire [NSAMP*SB_BITS-1:0] tripletA1;
            wire [NSAMP*SB_BITS-1:0] tripletB1;
            wire [NSAMP*SB_BITS-1:0] doublet1;
            
            wire [3:0] trigger_out;
            assign trigger_o[b + 0] = trigger_out[0];
            assign trigger_o[NBEAMS + b + 0] = trigger_out[1];

            if (b+1 < NBEAMS) begin : B2
                localparam int beam_content1[0:2] = (FULL == "TRUE") ? beam_contents_full[b+1] :
                                                                       beam_contents_dummy[b+1];
                int doublet1_idx =
                (beam_content1[2] >= NDOUBLETS) ? NDOUBLETS :
                                                  beam_content1[2];
                assign tripletA1 = triplets[beam_content1[0]];
                assign tripletB1 = triplets[beam_content1[1]];
                assign doublet1 = doublets[doublet1_idx];                                
                assign trigger_o[b + 1] = trigger_out[2];
                assign trigger_o[NBEAMS + b + 1] = trigger_out[3];
            end else begin : NB2
                assign tripletA1 = {NSAMP*SB_BITS{1'b0}};
                assign tripletB1 = {NSAMP*SB_BITS{1'b0}};
                assign doublet1 = {NSAMP*SB_BITS{1'b0}};
            end
            wire [NSAMP*3*SB_BITS-1:0] beam0 = { doublet0, tripletB0, tripletA0 };
            wire [NSAMP*3*SB_BITS-1:0] beam1 = { doublet1, tripletB1, tripletA1 };
            dual_pueo_beam_v2 #(.INTYPE("POSTADD"),
                                .DEBUG(DEBUG),
                                .CASCADE(b == 0 ? "FALSE" : "TRUE"))
             u_beamform(.clk_i(clk_i),
                        .beamA_i(beam0), 
                        .beamB_i(beam1),
                        .thresh_i(thresh_i),
                        .thresh_wr_i(thresh_wr_i),
                        .thresh_update_i(thresh_update_i),
                        .trigger_o(trigger_out),
                        .thresh_casc_i(cascade[b]),
                        .thresh_casc_o(cascade[(b + 2) % NBEAMS]));
        end
        // RIGHT NOW THE SAMPLES RUN IN REVERSE....
        for(chan_idx=0; chan_idx<NCHAN; chan_idx++) begin : CS
            // Partition Lucas's storage logic into its own module
            // so we can reuse it for the sub-beam storage later
            sample_store #(.PIPE("TRUE"),
                           .SAMPLE_STORE_DEPTH(SAMPLE_STORE_DEPTH),
                           .NBITS(NBITS),
                           .NSAMP(NSAMP))
                u_store(.clk_i(clk_i),
                        .dat_i(data_i[chan_idx]),
                        .store_o(sample_store[chan_idx]));
        end

        for (t=0;t<NTRIPLETS;t=t+1) begin : T
            localparam int triplet_delay[0:2] = (FULL == "TRUE") ? triplet_delay_full[t] :
                                                                   triplet_delay_dummy[t];
            localparam int triplet_index[0:2] = (FULL == "TRUE") ? triplet_index_full[t] :
                                                                   triplet_index_dummy[t];                                                                   

            for (t_ch=0;t_ch<3;t_ch=t_ch+1) begin : C
                int t_d = (SAMPLE_STORE_DEPTH-1)*NSAMP - triplet_delay[t_ch];
                assign triplets_delayed[t][t_ch] = sample_store[triplet_index[t_ch]][(t_d)*NBITS +: NSAMP*NBITS];
            end
            sub_beam u_tb(.clk_i(clk_i),
                          .chA_i(triplets_delayed[t][0]),
                          .chB_i(triplets_delayed[t][1]),
                          .chC_i(triplets_delayed[t][2]),
                          .dat_o(triplets[t]));
        end
        for (d=0;d<NDOUBLETS;d=d+1) begin : D
            localparam int doublet_delay[0:1] = (FULL == "TRUE") ? doublet_delay_full[d] :
                                                                   doublet_delay_dummy[d];
            for (d_ch=0;d_ch<2;d_ch=d_ch+1) begin : C
                localparam idx = (d_ch == 1) ? 4 : 0;
                int a_d = (SAMPLE_STORE_DEPTH-1)*NSAMP - doublet_delay[d][d_ch];                
                assign doublets_delayed[d][d_ch] = sample_store[idx][(a_d)*NBITS +: NSAMP*NBITS];
            end
            sub_beam u_db(.clk_i(clk_i),
                          .chA_i(doublets_delayed[d][0]),
                          .chB_i(doublets_delayed[d][1]),
                          .chC_i({NSAMP{5'd4}}),
                          .dat_o(doublets[d]));
        end
        assign doublets[NDOUBLETS] = { {NSAMP{7'd4}} };
    endgenerate           
    
endmodule
