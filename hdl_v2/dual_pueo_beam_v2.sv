`timescale 1ns / 1ps
// Second version of the 2 beam module. Because of COURSE we have to have two thresholds. Why
// wouldn't we need two thresholds. This version separates out the thresholding so if I
// change this I don't need to change that. So now we go from 2 DSPs to 4. Joy.

// This version has all the steps (add up and square, envelope form, threshold) separated
// out into new modules.

// This version calculates an 8-sample boxcar and decimates by a factor of 4.
// This leaves 2 samples per. But we only care about the MAXIMUM of those
// two samples, so we actually calculate sum([7:4]), sum([3:0]), and then
// we subtract sum([3:0])z^-1 - sum([3:0]), and if it's positive, we
// add it to (sum([7:4]) + sum([3:0]) to effectively create the max of
// the two samples.

// If INTYPE is RAW, just pass NCHAN*NSAMP*NBITS, the totally-raw input from
// all of the delayed beams.
//
// If INTYPE is POSTADD, pass 3*NSAMP*(NBITS+2) bits, the post-ternary adder
// inputs (ternary/ternary/binary).

// The beam modules should be combined *in cascade* for the thresholds.
module dual_pueo_beam_v2
                      #(parameter INTYPE = "RAW",           // either RAW or POSTADD.
                        parameter CASCADE = "TRUE",         // first is false, everyone else is true
                        // thank you, SystemVerilog 2009
                        localparam NBITS=5,
                        localparam NSAMP=8,
                        localparam NCHAN=8,
                        localparam INBITS = (INTYPE == "RAW") ? NCHAN*NSAMP*NBITS : 3*NSAMP*(NBITS+2)
                        ) (
        input clk_i,
        input [INBITS-1:0] beamA_i,
        input [INBITS-1:0] beamB_i,

        input [2*18-1:0] thresh_i,      //! first guy uses this
        input [1:0]   thresh_wr_i,      //! everyone uses this
        input [1:0]   thresh_update_i,  //! everyone uses this
        
        output [3:0] trigger_o,         //! raw trigger output
        
        input [47:0] thresh_casc_i,     //! only used if CASCADE is true
        output [47:0] thresh_casc_o
    );

    wire [NSAMP-1:0][13:0] squareA;     //! 8 samples of the squared beam for beam A
    wire [NSAMP-1:0][13:0] squareB;     //! 8 samples of the squared beam for beam B
    
    wire [NSAMP-1:0][(NBITS+3)-1:0] dbgA; //! Formed beam for beam A, for debugging
    wire [NSAMP-1:0][(NBITS+3)-1:0] dbgB; //! Formed beam for beam B, for debugging
            
    wire [17:0] envelopeA; //! Formed envelope for beam A
    wire [17:0] envelopeB; //! Formed envelope for beam B
        
    dual_pueo_beamform_v2 #(.INTYPE(INTYPE))
        u_beamform(.clk_i(clk_i),
                   .beamA_i(beamA_i),
                   .beamB_i(beamB_i),
                   .outA_o(dbgA),
                   .outB_o(dbgB),
                   .sq_outA_o(squareA),
                   .sq_outB_o(squareB));

    dual_pueo_envelope_v2
        u_envelope(.clk_i(clk_i),
                   .squareA_i(squareA),
                   .squareB_i(squareB),
                   .envelopeA_o( envelopeA[16:0] ),
                   .envelopeB_o( envelopeB[16:0] ));
    
    assign envelopeA[17] = 1'b0;
    assign envelopeB[17] = 1'b0;

    dual_pueo_threshold_v2 #(.CASCADE(CASCADE))
        u_threshold( .clk_i(clk_i),
                     .thresh_i(thresh_i),
                     .thresh_wr_i(thresh_wr_i),
                     .thresh_update_i(thresh_update_i),
                     .envelope_i( { envelopeB, envelopeA } ),
                     .trigger_o(trigger_o),
                     .ab_casc_i(thresh_casc_i),
                     .ab_casc_o(thresh_casc_o));
    
endmodule
