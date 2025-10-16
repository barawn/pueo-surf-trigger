`timescale 1ns / 1ps

`include "dsp_macros.vh"
// LF envelope generation. 48-fold running sum sampled every 4.
// This version just uses 4 DSPs for 2 beams.
// The inputs act like 14 bits, but they're really
// just a sum of 5 5-bit values ranging from -15.5 to +15.5,
// yielding 77.5^2 = 6006.25, so the 48 fold sum really has a range
// of 19 bits, but to be compatible with the old module right now
// we downshift by 3 at the end. Check with the LF people about this,
// it's mostly pointless.
//
// n.b. Also check about the incorrect square, in the previous
// beamform it's still wrong. Need to add the input to the square
// out to adjust back. This leaves off the 0.25 present on
// each one, but that's just a constant offset and doesn't matter
// (unlike the wrong square which does).

// really I should just call this dual_pueo_running_sum or something.
//
// Note that we can't really use the sleaze sum of 4 because
// these aren't (or shouldn't) be true integer squares, since
// they were offset by 0.5.
// So for instance you get 77.5 squared which is 6006.25,
// which even if you look at the integer part doesn't match
// a square since it has the twos bit set.
//
// If we ignore the 0.5 offset, we get an asymmetric bias, since
// if we add 5x15.5, we're going to get 77 (should be 77.5)
// and if we add 5x(-15.5) we're going to get -78 (should be -77.5)
// and the *positive* square becomes 5929 and the negative
// square becomes 6084.
//
// The v2c version saves a DSP and a bunch of SRLs by
// instead doing 3 chained DSPs, with the first 2 computing
// the sum of 4 and then that sum delayed to subtract off.
module dual_pueo_lowampa_envelope_v2c #(localparam NBITS=14,
                                        localparam NSAMP=4,
                                        parameter SUM_DELAY=12,
                                        parameter OUTBITS=17,
                                        parameter OUTSHIFT=3)(
        input clk_i,
        input [NBITS*NSAMP-1:0] squareA_i,
        input [NBITS*NSAMP-1:0] squareB_i,
        
        output [OUTBITS-1:0] envelopeA_o,
        output [OUTBITS-1:0] envelopeB_o        
    );
    
    // We sum everything using 4 DSPs, which gives us 8 total add slots.
    // We add each sample in 4 of them and subtract the delayed version
    // of each input as well, and then accumulate in the last DSP.
    //
    // For inputs A, B, C, D, this gives us
    // (A+B+C+D) = x
    // y = x - xz^-12 + yz^-1
    // which is a transfer function of
    // (1-z^-12)/(1-z^-1) = 1+z^-1 + z^-2... + z^-11.
    
    // With cascaded DSPs, we CAN add two of them in a single clock,
    // so we organize this as:
    //
    // A        ->  (AB)z^-1    \+________
    // B        ->   (C)z^-1    /          \
    // C        ->  (AB)z^-1    -----------+__z^-1______x___
    // D        ->   (C)z^-1    -----------/      |
    // ~xz^-11  ->   (C)z^-1    ------------------+---z^-1---- output
    //                                            |        |
    //                                            \--------/
    // This is y = x - xz^-12 + yz^-1.    
    // First two DSPs do X=AB, Y=C, P = X+Y
    // Third DSP does X=P, Y=C, Z=PCIN, W=RND, P = X+Y+Z+W where
    // RND is 48'h000001000001 to handle the subtraction.
    //
    // We're adding 4x 14 bit squares together so we need a 16-bit delay.
    // This could actually be trimmed because we can't actually reach it.
    // Worry about that later.
    
    // cascade chains
    wire [47:0] dspA_to_dspB;
    wire [47:0] dspB_to_dspC;

    wire [47:0] dspC_out;
    wire [47:0] dspB_out;
    wire [1:0][(NBITS+2)-1:0] sqin;
    assign sqin[0] = dspB_out[0 +: (NBITS+2)];
    assign sqin[1] = dspB_out[24 +: (NBITS+2)];    
    
    // pipe registers
    reg [NSAMP-1:0][NBITS-1:0] squareA = {NSAMP*NBITS{1'b0}};
    reg [NSAMP-1:0][NBITS-1:0] squareB = {NSAMP*NBITS{1'b0}};

    // delays out of the FF
    wire [(NBITS+2)-1:0] squareA_srl;
    wire [(NBITS+2)-1:0] squareB_srl;
    
    // delay register
    reg [(NBITS+2)-1:0] squareA_delay = {(NBITS+2){1'b0}};
    reg [(NBITS+2)-1:0] squareB_delay = {(NBITS+2){1'b0}};

    generate
        genvar i;
        for (i=0;i<NSAMP;i=i+1) begin : DLY
            always @(posedge clk_i) begin : FF
                squareA[i] <= squareA_i[NBITS*i +: NBITS];
                squareB[i] <= squareB_i[NBITS*i +: NBITS];
            end
        end
    endgenerate    

    // total delay needs to be z^-11, with an extra z^-1 picked
    // up in the SRL FF so we need an address of 9
    srlvec #(.NBITS(NBITS+2)) u_dlyA(.clk(clk_i),.ce(1'b1),.a(9),
                                    .din(~sqin[0]),
                                    .dout(squareA_srl));
    srlvec #(.NBITS(NBITS+2)) u_dlyB(.clk(clk_i),.ce(1'b1),.a(9),
                                    .din(~sqin[1]),
                                    .dout(squareB_srl));
    always @(posedge clk_i) begin
        squareA_delay <= squareA_srl;
        squareB_delay <= squareB_srl;
    end                                                                        

    localparam [8:0] dspA_OPMODE = { `W_OPMODE_0, `Z_OPMODE_0, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [3:0] dspA_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [47:0] dspA_AB = { {(24-NBITS){1'b0}}, squareB[0],
                            {(24-NBITS){1'b0}}, squareA[0] };
    wire [47:0] dspA_C  = { {(24-NBITS){1'b0}}, squareB[1],
                            {(24-NBITS){1'b0}}, squareA[1] };
    localparam [8:0] dspB_OPMODE = { `W_OPMODE_0, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [3:0] dspB_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [47:0] dspB_AB = { {(24-NBITS){1'b0}}, squareB[2],
                            {(24-NBITS){1'b0}}, squareA[2] };
    wire [47:0] dspB_C  = { {(24-NBITS){1'b0}}, squareB[3],
                            {(24-NBITS){1'b0}}, squareA[3] };

    localparam [8:0] dspC_OPMODE = { `W_OPMODE_RND, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_P};
    localparam [8:0] dspC_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    localparam [47:0] dspC_RND = 48'h000001000001;

    wire [47:0] dspC_C  = { {(24-(NBITS+2)){squareB_delay[(NBITS+2)-1]}}, squareB_delay,
                            {(24-(NBITS+2)){squareA_delay[(NBITS+2)-1]}}, squareA_delay };
    
    two24_dsp #(.ABREG(1),
                .CREG(1),
                .PREG(0),
                .CASCADE("FALSE"),
                .OPMODE(dspA_OPMODE),
                .ALUMODE(dspA_ALUMODE))
                u_dspA(.clk_i(clk_i),
                       .AB_i(dspA_AB),
                       .C_i(dspA_C),
                       .pc_o(dspA_to_dspB));
    two24_dsp #(.ABREG(1),
                .CREG(1),
                .PREG(1),
                .CASCADE("TRUE"),
                .OPMODE(dspB_OPMODE),
                .ALUMODE(dspB_ALUMODE))
                u_dspB(.clk_i(clk_i),
                       .AB_i(dspB_AB),
                       .C_i(dspB_C),
                       .pc_i(dspA_to_dspB),
                       .P_o(dspB_out),
                       .pc_o(dspB_to_dspC));
    two24_dsp #(.USE_AB(0),
                .CREG(1),
                .PREG(1),
                .CASCADE("TRUE"),
                .RND(dspC_RND),
                .OPMODE(dspC_OPMODE),
                .ALUMODE(dspC_ALUMODE))
                u_dspC(.clk_i(clk_i),
                       .C_i(dspC_C),
                       .pc_i(dspB_to_dspC),
                       .P_o(dspC_out));
                       
    assign envelopeA_o = dspC_out[OUTSHIFT +: OUTBITS];
    assign envelopeB_o = dspC_out[24+OUTSHIFT +: OUTBITS];
                               
endmodule
