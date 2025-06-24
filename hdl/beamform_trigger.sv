`timescale 1ns / 1ps
`include "L1Beams_header.vh"
// 2 beam module.
// Each beam input takes in 8x8x5 = 320 total inputs in OFFSET BINARY.
// They are organized as { ch7[39:0], ch6[39:0], ch5[39:0], ch4[39:0], ch3[39:0], ch2[39:0], ch1[39:0], ch0[39:0] }
// with chX = { samp7[4:0], samp6[4:0], samp5[4:0], samp4[4:0], samp3[4:0], samp2[4:0], samp1[4:0], samp0[4:0] }

// `define BEAM_ANTENNA_DELAYS '{ '{1,4,2,0,3,4,2,0}, '{0,5,3,1,2,4,2,0}, '{0,4,2,0,2,5,3,1}, '{0,5,4,2,2,5,4,2}, '{0,7,5,4,2,6,5,3}, '{0,6,5,3,2,7,5,4}, '{0,8,6,5,2,8,6,5}, '{0,8,7,6,1,7,6,5}, '{0,8,7,6,2,9,8,7}, '{0,10,9,8,2,10,9,8}, '{0,10,10,9,1,9,9,8}, '{0,9,9,8,1,10,10,9}, '{0,11,11,10,1,11,11,10}, '{0,12,12,12,1,12,11,11}, '{0,12,11,11,1,12,12,12}, '{0,13,13,13,0,13,13,13}, '{0,14,14,14,1,15,15,15}, '{0,15,15,15,0,14,14,14}, '{0,15,16,17,0,15,16,17}, '{0,16,17,18,1,17,18,18}, '{1,17,18,18,0,16,17,18}, '{1,17,19,20,0,17,19,20}, '{0,17,18,20,0,18,19,21}, '{1,19,20,22,0,18,19,21}, '{1,20,21,23,0,20,21,23}, '{1,21,23,25,0,20,22,24}, '{1,20,22,24,0,21,23,25}, '{1,22,24,26,0,22,24,26}, '{2,23,25,28,0,22,25,27}, '{1,22,25,27,0,23,25,28}, '{2,24,26,29,0,24,26,29}, '{2,25,28,31,0,24,27,30}, '{2,24,27,30,0,25,28,31}, '{2,26,29,32,0,26,29,32}, '{2,27,31,34,0,27,30,33}, '{2,27,30,33,0,27,31,34}, '{2,28,32,35,0,28,32,35}, '{3,29,33,37,0,29,33,36}, '{2,29,33,36,0,29,33,37}, '{3,30,34,38,0,30,34,38}, '{3,31,36,40,0,31,35,40}, '{3,31,35,40,0,31,36,40}, '{3,32,37,41,0,32,37,41}, '{4,33,38,43,0,33,38,43}, '{3,33,38,43,0,34,38,43}, '{4,34,39,45,0,34,39,45} }


module beamform_trigger #(  parameter NBEAMS = 2,
                            parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK") (
        input clk_i,
        input [NCHAN-1:0][NSAMP*NBITS-1:0] data_i,

        input [17:0] thresh_i,
        input [NBEAMS-1:0] thresh_ce_i,
        input update_i,        
        
        output [NBEAMS-1:0] trigger_o
    );

    // Moving these to localparams, since this module will break with unexpected values.
    localparam NBITS=5;
    localparam NSAMP=8; 
    localparam NCHAN=8;
    localparam SAMPLE_STORE_DEPTH = 8+2; // The +2 is for aligning antenna 0 to the same place every time, even with a "negative delay"

    generate
        if(`MAX_ANTENNA_DELAY_0 > 8) begin: THROW_AN_ERROR
            channel_0_max_antenna_delay_bigger_than_8 errormod();
        end
    endgenerate

    // localparam NBEAMS_AVAILABLE = 45;

    // NOTE THE BIG-ENDIAN ARRAYS HERE
    localparam int delay_array [0:(`BEAM_TOTAL)-1][0:NCHAN-1] = `BEAM_ANTENNA_DELAYS;

    reg  [SAMPLE_STORE_DEPTH*NSAMP*NBITS-1:0] sample_store [NCHAN-1:0];
    wire [NCHAN-1:0][NSAMP*NBITS-1:0] beams_delayed [NBEAMS-1:0];
    wire [NSAMP-1:0][NBITS-1:0] vectorized_delayed_data [NBEAMS-1:0][NCHAN-1:0];

    genvar beam_idx, chan_idx, clock_idx, samp_idx;

    generate

        // Vectorize for debugging
        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin
            for(chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
                for(samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                    assign vectorized_delayed_data[beam_idx][chan_idx][samp_idx] = beams_delayed[beam_idx][chan_idx][samp_idx*NBITS +: NBITS];
                end
            end
        end

        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin : ALIGNMENT
            for(chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
                // The first term below makes sure that antenna 0 always has a delay of 8. 
                // If another antenna has a delay of 0, as long as antenna 0 has a max delay < 8 all should be good.
                int sample_delay = (SAMPLE_STORE_DEPTH-1)*NSAMP - ((8 - delay_array[beam_idx][0]) + delay_array[beam_idx][chan_idx]);
                assign beams_delayed[beam_idx][chan_idx] = sample_store[chan_idx][( sample_delay )*NBITS +: NSAMP*NBITS];
            end
        end

        for(beam_idx=0; beam_idx<NBEAMS; beam_idx = beam_idx+2) begin: DUAL_BEAMFORMERS
            if(beam_idx+1<NBEAMS) begin: DUAL_USE
                dual_pueo_beam u_beamform(
                    .clk_i(clk_i),
                    .beamA_i(beams_delayed[beam_idx + 0]), // Beam A corresponds to the MSB of the trigger bits
                    .beamB_i(beams_delayed[beam_idx + 1]),
                    .thresh_i(thresh_i),
                    .thresh_ce_i(thresh_ce_i[beam_idx +: 2]),
                    .update_i(update_i),        
                    .trigger_o(trigger_o[beam_idx +: 2])
                );
            end else begin: SINGLE_USE
                wire empty;
                dual_pueo_beam u_beamform_single(
                    .clk_i(clk_i),
                    .beamA_i(beams_delayed[beam_idx + 0]),
                    .beamB_i(beams_delayed[beam_idx + 0]),
                    .thresh_i(thresh_i),
                    .thresh_ce_i({thresh_ce_i[beam_idx], thresh_ce_i[beam_idx]}),
                    .update_i(update_i),        
                    .trigger_o({trigger_o[beam_idx], empty})
                );
            end
        end


        // RIGHT NOW THE SAMPLES RUN IN REVERSE....
        for(chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
            for(clock_idx=SAMPLE_STORE_DEPTH-2; clock_idx>=0;clock_idx--) begin
                always @(posedge clk_i) begin: SHIFT_SAMPLE_STORE
                    sample_store[chan_idx][clock_idx*NSAMP*NBITS +: NSAMP*NBITS] <= sample_store[chan_idx][(clock_idx+1)*NSAMP*NBITS +: NSAMP*NBITS]; // Shift over
                end
            end
            always @(posedge clk_i) begin: NEW_SAMPLE_STORE
                sample_store[chan_idx][(SAMPLE_STORE_DEPTH-1)*NSAMP*NBITS +: NSAMP*NBITS] <= data_i[chan_idx]; // New one goes in
            end
        end 
    endgenerate

endmodule