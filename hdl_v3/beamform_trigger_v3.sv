`timescale 1ns / 1ps
`include "pueo_beams_09_04_25.sv"
`include "pueo_dummy_beams.sv"
// Just for clarity, call out all the parameters used from the package

// get number of beams in package
import pueo_beams::NUM_BEAM;
// get sample store depth
import pueo_beams::SAMPLE_STORE_DEPTH;
// get number of left adders
import pueo_beams::LEFT_ADDER_LEN;
// get sample store depth for left adders
import pueo_beams::LEFT_STORE_DEPTH;
// get number of right adders
import pueo_beams::RIGHT_ADDER_LEN;
// get sample store depth for right adders
import pueo_beams::RIGHT_STORE_DEPTH;
// get number of top adders
import pueo_beams::TOP_ADDER_LEN;
// get sample store depth for top adders
import pueo_beams::TOP_STORE_DEPTH;

// get adders
import pueo_beams::LEFT_ADDERS;
import pueo_beams::RIGHT_ADDERS;
import pueo_beams::TOP_ADDERS;

// get beams and offsets
import pueo_beams::BEAM_INDICES;
import pueo_beams::BEAM_LEFT_OFFSETS;
import pueo_beams::BEAM_RIGHT_OFFSETS;
import pueo_beams::BEAM_TOP_OFFSETS;

// get everything from the dummy package - same as the above guys
import pueo_dummy_beams::*;

module beamform_trigger_v3 #(parameter FULL = "TRUE",
                             parameter DEBUG = "FALSE",
                             localparam NBEAMS = (FULL == "TRUE") ? NUM_BEAM : NUM_DUMMY,
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
    
    localparam int LEFT_INDICES[0:2] = '{ 5, 6, 7 };
    localparam int RIGHT_INDICES[0:2] = '{ 1, 2, 3 };
    localparam int TOP_INDICES[0:1] = '{ 0, 4 }; 

    // number of bits in the sub-beams.    
    localparam SB_BITS = 7;
    
    // These get selected here, later ones have to get pulled in the generate
    // loops.
    localparam int NUM_RIGHT_ADDERS = (FULL == "TRUE") ? RIGHT_ADDER_LEN :
                                                         RIGHT_ADDER_LEN_DUMMY;
    localparam int NUM_LEFT_ADDERS = (FULL == "TRUE") ? LEFT_ADDER_LEN :
                                                        LEFT_ADDER_LEN_DUMMY;
    localparam int NUM_TOP_ADDERS = (FULL == "TRUE") ? TOP_ADDER_LEN :
                                                       TOP_ADDER_LEN_DUMMY;
    localparam int NUM_SAMPLE_STORE = (FULL == "TRUE") ? SAMPLE_STORE_DEPTH :
                                                     SAMPLE_STORE_DUMMY;
    localparam int NUM_RIGHT_STORE = (FULL == "TRUE") ? RIGHT_STORE_DEPTH :
                                                   RIGHT_STORE_DEPTH_DUMMY;
    localparam int NUM_LEFT_STORE = (FULL == "TRUE") ? LEFT_STORE_DEPTH :
                                                   LEFT_STORE_DEPTH_DUMMY;
    
    // sample storage
    wire [NUM_SAMPLE_STORE*NSAMP*NBITS-1:0] sample_store[NCHAN-1:0];
    // adder inputs
    wire [2:0][NSAMP*NBITS-1:0] left_triplet_inputs[NUM_LEFT_ADDERS-1:0];
    wire [2:0][NSAMP*NBITS-1:0] right_triplet_inputs[NUM_RIGHT_ADDERS-1:0];
    wire [1:0][NSAMP*NBITS-1:0] top_doublet_inputs[NUM_TOP_ADDERS-1:0];
    
    // adder outputs
    wire [NSAMP*SB_BITS-1:0] left_triplets[NUM_LEFT_ADDERS-1:0];
    wire [NSAMP*SB_BITS-1:0] right_triplets[NUM_RIGHT_ADDERS-1:0];
    wire [NSAMP*SB_BITS-1:0] top_doublets[NUM_TOP_ADDERS-1:0];
    
    // adder storage
    wire [NUM_LEFT_STORE*NSAMP*SB_BITS-1:0] left_store[NUM_LEFT_ADDERS-1:0];
    wire [NUM_RIGHT_STORE*NSAMP*SB_BITS-1:0] right_store[NUM_LEFT_ADDERS-1:0];
    // there is no top store

    // stupidity but whatever
    wire [47:0] cascade[NBEAMS-1:0];
    
    generate
        genvar ch, l, r, t, l_ch, r_ch, t_ch, b;
        for (ch=0;ch<NCHAN;ch=ch+1) begin : SS
            sample_store #(.NBITS(NBITS),
                           .NSAMP(8),
                           .SAMPLE_STORE_DEPTH(NUM_SAMPLE_STORE),
                           .PIPE("TRUE"))
                           u_store(.clk_i(clk_i),
                                   .dat_i(data_i[ch]),
                                   .store_o(sample_store[ch]));
        end
        for (l=0;l<NUM_LEFT_ADDERS;l=l+1) begin : LA
            if (NUM_LEFT_STORE > 1) begin : LS
                sample_store #(.NBITS(SB_BITS),
                               .NSAMP(8),
                               .SAMPLE_STORE_DEPTH(NUM_LEFT_STORE))
                               u_store(.clk_i(clk_i),
                                       .dat_i(left_triplets[l]),
                                       .store_o(left_store[l]));
            end else begin : NLS
                assign left_store[l] = left_triplets[l];
            end
            // create the sub-beams
            // get the delay
            localparam int left_delay[0:2] = (FULL == "TRUE") ? LEFT_ADDERS[l] :
                                                                LEFT_ADDERS_DUMMY[l];
            // find the inputs                                                                
            for (l_ch=0;l_ch<3;l_ch=l_ch+1) begin : LC
                int l_d = (NUM_SAMPLE_STORE-1)*NSAMP - left_delay[l_ch];
                assign left_triplet_inputs[l][l_ch] = sample_store[LEFT_INDICES[l_ch]][(l_d)*NBITS +: NSAMP*NBITS];                
            end
            // and feed into the adder
            sub_beam u_lb(.clk_i(clk_i),
                          .chA_i(left_triplet_inputs[l][0]),
                          .chB_i(left_triplet_inputs[l][1]),
                          .chC_i(left_triplet_inputs[l][2]),
                          .dat_o(left_triplets[l]));
        end
        for (r=0;r<NUM_RIGHT_ADDERS;r=r+1) begin : RA
            if (NUM_RIGHT_STORE > 1) begin : RS
                sample_store #(.NBITS(SB_BITS),
                               .NSAMP(8),
                               .SAMPLE_STORE_DEPTH(NUM_LEFT_STORE))
                               u_store(.clk_i(clk_i),                               
                                       .dat_i(right_triplets[r]),
                                       .store_o(right_store[r]));
            end else begin : NRS
                assign right_store[r] = right_triplets[r];
            end
            // create the sub-beams
            // get the delay
            localparam int right_delay[0:2] = (FULL == "TRUE") ? RIGHT_ADDERS[r] :
                                                                 RIGHT_ADDERS_DUMMY[r];
            // find the inputs                                                                
            for (r_ch=0;r_ch<3;r_ch=r_ch+1) begin : LC
                int r_d = (NUM_SAMPLE_STORE-1)*NSAMP - right_delay[r_ch];
                assign right_triplet_inputs[r][r_ch] = sample_store[RIGHT_INDICES[r_ch]][(r_d)*NBITS +: NSAMP*NBITS];                
            end
            // and feed into the adder
            sub_beam u_rb(.clk_i(clk_i),
                          .chA_i(right_triplet_inputs[r][0]),
                          .chB_i(right_triplet_inputs[r][1]),
                          .chC_i(right_triplet_inputs[r][2]),
                          .dat_o(right_triplets[r]));
        end
        for (t=0;t<NUM_TOP_ADDERS;t=t+1) begin : TA
            // no top store
            // create the sub-beams
            // get the delay
            localparam int top_delay[0:1] = (FULL == "TRUE") ? TOP_ADDERS[t] :
                                                               TOP_ADDERS_DUMMY[t];
            for (t_ch=0;t_ch<2;t_ch=t_ch+1) begin : TC
                int t_d = (NUM_SAMPLE_STORE-1)*NSAMP - top_delay[t_ch];
                assign top_doublet_inputs[t][t_ch] = sample_store[TOP_INDICES[t_ch]][(t_d)*NBITS +: NSAMP*NBITS];
            end
            // and feed into the adder
            sub_beam u_tb(.clk_i(clk_i),
                          .chA_i(top_doublet_inputs[t][0]),
                          .chB_i(top_doublet_inputs[t][1]),
                          .chC_i({NSAMP{5'd4}}),
                          .dat_o(top_doublets[t]));
        end
        // and now we build the beams
        for (b=0;b<NBEAMS;b=b+1) begin : BB
            wire [NSAMP*3*SB_BITS-1:0] beam0;
            wire [NSAMP*3*SB_BITS-1:0] beam1;
            wire [3:0] trigger_out;
            // First beam.        
            localparam int left_index = (FULL == "TRUE") ? BEAM_INDICES[b][0] :
                                                           BEAM_INDICES_DUMMY[b][0];
            localparam int right_index = (FULL == "TRUE") ? BEAM_INDICES[b][1] :
                                                            BEAM_INDICES_DUMMY[b][1];
            localparam int top_index = (FULL == "TRUE") ? BEAM_INDICES[b][2] :
                                                          BEAM_INDICES_DUMMY[b][2];

            localparam int left_offset = (FULL == "TRUE") ? BEAM_LEFT_OFFSETS[b] :
                                                            BEAM_LEFT_OFFSETS_DUMMY[b];
            localparam int right_offset = (FULL == "TRUE") ? BEAM_RIGHT_OFFSETS[b] :
                                                            BEAM_RIGHT_OFFSETS_DUMMY[b];
            
            // This starts at the beginning of the end and we move forward
            // Note that if num left store/num right store are 1, left offset/right offset has to be zero.
            localparam int left_delay = (NUM_LEFT_STORE-1)*NSAMP - left_offset;
            localparam int right_delay = (NUM_RIGHT_STORE-1)*NSAMP - right_offset;            
            
            wire [NSAMP*SB_BITS-1:0] left_input = left_store[left_index][(left_delay)*SB_BITS +: NSAMP*SB_BITS];
            wire [NSAMP*SB_BITS-1:0] right_input = right_store[right_index][(right_delay)*SB_BITS +: NSAMP*SB_BITS];
            wire [NSAMP*SB_BITS-1:0] top_input;
            
            if (top_index < NUM_TOP_ADDERS) begin : RT
                assign top_input = top_doublets[top_index];
            end else begin : FT
                localparam [SB_BITS-1:0] filler = 'd4;
                assign top_input = {NSAMP{filler}};
            end
            
            assign beam0 = { top_input, right_input, left_input };
            assign trigger_o[b + 0] = trigger_out[0];
            assign trigger_o[NBEAMS + b + 0] = trigger_out[1];
                        
            // second beam, if needed.
            if (b+1 < NBEAMS) begin : B2
                localparam int left_index1 = (FULL == "TRUE") ? BEAM_INDICES[b+1][0] :
                                                               BEAM_INDICES_DUMMY[b+1][0];
                localparam int right_index1 = (FULL == "TRUE") ? BEAM_INDICES[b+1][1] :
                                                                BEAM_INDICES_DUMMY[b+1][1];
                localparam int top_index1 = (FULL == "TRUE") ? BEAM_INDICES[b+1][2] :
                                                              BEAM_INDICES_DUMMY[b+1][2];
    
                localparam int left_offset1 = (FULL == "TRUE") ? BEAM_LEFT_OFFSETS[b+1] :
                                                                BEAM_LEFT_OFFSETS_DUMMY[b+1];
                localparam int right_offset1 = (FULL == "TRUE") ? BEAM_RIGHT_OFFSETS[b+1] :
                                                                BEAM_RIGHT_OFFSETS_DUMMY[b+1];
                
                // This starts at the beginning of the end and we move forward
                // Note that if num left store/num right store are 1, left offset/right offset has to be zero.
                localparam int left_delay1 = (NUM_LEFT_STORE-1)*NSAMP - left_offset1;
                localparam int right_delay1 = (NUM_RIGHT_STORE-1)*NSAMP - right_offset1;
                
                wire [NSAMP*SB_BITS-1:0] left_input1 = left_store[left_index1][(left_delay1)*SB_BITS +: NSAMP*SB_BITS];
                wire [NSAMP*SB_BITS-1:0] right_input1 = right_store[right_index1][(right_delay1)*SB_BITS +: NSAMP*SB_BITS];
                wire [NSAMP*SB_BITS-1:0] top_input1;
                if (top_index1 < NUM_TOP_ADDERS) begin : RT
                    assign top_input1 = top_doublets[top_index1];
                end else begin : FT
                    localparam [SB_BITS-1:0] filler = 'd4;
                    assign top_input1 = {NSAMP{filler}};
                end
                assign beam1 = { top_input1, right_input1, left_input1 };
                assign trigger_o[ b + 1 ] = trigger_out[2];
                assign trigger_o[ NBEAMS + b + 1 ] = trigger_out[3];
            end else begin : NB2
                assign beam1 = {NSAMP*3*SB_BITS{1'b0}};
                // Don't need to assign the trigger because its index doesn't exist.
            end
            
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
                           .thresh_casc_o(cascade[(b+2) % NBEAMS]));                                
        end
    endgenerate

endmodule
