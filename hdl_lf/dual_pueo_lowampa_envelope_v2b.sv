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
module dual_pueo_lowampa_envelope_v2b #(localparam NBITS=14,
                                        localparam NSAMP=4,
                                        parameter SUM_DELAY=12,
                                        parameter OUTBITS=17,
                                        parameter OUTSHIFT=3)(
        input clk_i,
        input rst_i,
        input [NBITS*NSAMP-1:0] squareA_i,
        input [NBITS*NSAMP-1:0] squareB_i,
        
        output [OUTBITS-1:0] envelopeA_o,
        output [OUTBITS-1:0] envelopeB_o        
    );
    
    // The sum fundamentally is an IIR with compensating
    // FIR terms to generate the running sum. IIRs obviously
    // have trouble if the clock isn't stable, so we need
    // a reset if something's not locked.
    //
    // We stretch the hell out of the reset just to be safe.
    // We only really need to reset the final DSP. Everyone else
    // just freely clocks and eventually clears out well before
    // we hit the 16-clock reset anyway.
    reg [1:0] sum_reset_fall = 0;
    reg sum_reset = 0;
    reg [4:0] sum_reset_counter = {5{1'b0}};
    
    always @(posedge clk_i) begin
        sum_reset_fall <= { sum_reset_fall[0], rst_i };
        
        if (sum_reset_fall[1] && !sum_reset_fall[0]) sum_reset <= 1;
        else if (sum_reset_counter[4]) sum_reset <= 0;
        
        if (sum_reset) sum_reset_counter <= sum_reset_counter[3:0] + 1;
        else sum_reset_counter <= {5{1'b0}};
    end
    
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
    // Az^-10    ->  (AB)z^-1    \+___z^-1__
    // Bz^-10   ->   (C)z^-1    /          \
    // Cz^-11   ->  (AB)z^-1    -----------+__z^-1__
    // Dz^-11   ->   (C)z^-1    -----------/        \
    // A        ->  (AB)z^-1    --------------------+------   _______
    // B        ->   (C)z^-1    --------------------/      \ /       \
    // C        ->  (AB)z^-1    ----------------------------+___z^-1__|___output
    // D        ->   (C)z^-1    ----------------------------|
    //
    // The first DSP does X=AB, Y=C, and P= -X-Y
    // The second DSP does X=AB, Y=C, Z=PCIN, and P = Z - X - Y
    // The third DSP does X=AB, Y=C, Z=PCIN, and P = Z + X + Y
    // The fourth DSP does X=AB, Y=C, Z=PCIN, W=Pz^-1, and P = Z + X + Y + W.
    
    // cascade chains
    wire [47:0] dspA_to_dspB;
    wire [47:0] dspB_to_dspC;
    wire [47:0] dspC_to_dspD;

    wire [47:0] dspD_out;

    // pipe registers
    reg [NSAMP-1:0][NBITS-1:0] squareA = {NSAMP*NBITS{1'b0}};
    reg [NSAMP-1:0][NBITS-1:0] squareB = {NSAMP*NBITS{1'b0}};
    // delay registers
    reg [NSAMP-1:0][NBITS-1:0] squareA_delay = {NSAMP*NBITS{1'b0}};
    reg [NSAMP-1:0][NBITS-1:0] squareB_delay = {NSAMP*NBITS{1'b0}};

    generate
        genvar i;
        for (i=0;i<NSAMP;i=i+1) begin : DLY
            // The total delay needs to be z^-10 for
            // 0/1 and z^-11 for 2/3.
            // We pick up one z^-1 in the output.
            // So the SRL needs 9/10 clocks,
            // or addresses of 8/9. This is
            // SUM_DELAY-4 and SUM_DELAY-3
            localparam [3:0] srl_dly = (i<2) ? SUM_DELAY-4 : SUM_DELAY-3;
            wire [NBITS-1:0] dlyA;
            wire [NBITS-1:0] dlyB;

            // SRLs always pair up with FFs otherwise it's a waste.
            // We take in the pipe register, not the input directly,
            // since there's no reason not to and the pipe register
            // is guaranteed to be close due to the cascades.
            srlvec #(.NBITS(NBITS)) u_dlyA(.clk(clk_i),.ce(1'b1),
                                           .a(srl_dly),
                                           .din(squareA[i]),
                                           .dout(dlyA));
            srlvec #(.NBITS(NBITS)) u_dlyB(.clk(clk_i),.ce(1'b1),
                                           .a(srl_dly),
                                           .din(squareB[i]),
                                           .dout(dlyB));
            always @(posedge clk_i) begin : FF
                squareA[i] <= squareA_i[NBITS*i +: NBITS];
                squareB[i] <= squareB_i[NBITS*i +: NBITS];
                squareA_delay[i] <= dlyA;
                squareB_delay[i] <= dlyB;
            end
        end
    endgenerate    
    localparam [8:0] dspA_OPMODE = { `W_OPMODE_0, `Z_OPMODE_0, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [3:0] dspA_ALUMODE = `ALUMODE_Z_MINUS_XYCIN;
    wire [47:0] dspA_AB = { {(24-NBITS){1'b0}}, squareB_delay[0],
                            {(24-NBITS){1'b0}}, squareA_delay[0] };
    wire [47:0] dspA_C  = { {(24-NBITS){1'b0}}, squareB_delay[1],
                            {(24-NBITS){1'b0}}, squareA_delay[1] };
    localparam [8:0] dspB_OPMODE = { `W_OPMODE_0, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [3:0] dspB_ALUMODE = `ALUMODE_Z_MINUS_XYCIN;
    wire [47:0] dspB_AB = { {(24-NBITS){1'b0}}, squareB_delay[2],
                            {(24-NBITS){1'b0}}, squareA_delay[2] };
    wire [47:0] dspB_C  = { {(24-NBITS){1'b0}}, squareB_delay[3],
                            {(24-NBITS){1'b0}}, squareA_delay[3] };
    localparam [8:0] dspC_OPMODE = { `W_OPMODE_0, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [8:0] dspC_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [47:0] dspC_AB = { {(24-NBITS){1'b0}}, squareB[0],
                            {(24-NBITS){1'b0}}, squareA[0] };
    wire [47:0] dspC_C  = { {(24-NBITS){1'b0}}, squareB[1],
                            {(24-NBITS){1'b0}}, squareA[1] };
    localparam [8:0] dspD_OPMODE = { `W_OPMODE_P, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB };
    localparam [8:0] dspD_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [47:0] dspD_AB = { {(24-NBITS){1'b0}}, squareB[2],
                            {(24-NBITS){1'b0}}, squareA[2] };
    wire [47:0] dspD_C  = { {(24-NBITS){1'b0}}, squareB[3],
                            {(24-NBITS){1'b0}}, squareA[3] };
    
    two24_dsp #(.ABREG(1),
                .CREG(1),
                .PREG(1),
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
                       .pc_o(dspB_to_dspC));
    two24_dsp #(.ABREG(1),
                .CREG(1),
                .PREG(0),
                .CASCADE("TRUE"),
                .OPMODE(dspC_OPMODE),
                .ALUMODE(dspC_ALUMODE))
                u_dspC(.clk_i(clk_i),
                       .AB_i(dspC_AB),
                       .C_i(dspC_C),
                       .pc_i(dspB_to_dspC),
                       .pc_o(dspC_to_dspD));
    two24_dsp #(.ABREG(1),
                .CREG(1),
                .PREG(1),
                .USE_RST(1),
                .CASCADE("TRUE"),
                .OPMODE(dspD_OPMODE),
                .ALUMODE(dspD_ALUMODE))
                u_dspD(.clk_i(clk_i),
                       .rst_ab_i(1'b0),
                       .rst_c_i(1'b0),
                       .rst_p_i(sum_reset),
                       .AB_i(dspD_AB),
                       .C_i(dspD_C),
                       .pc_i(dspC_to_dspD),
                       .P_o(dspD_out));
    assign envelopeA_o = dspD_out[OUTSHIFT +: OUTBITS];
    assign envelopeB_o = dspD_out[24+OUTSHIFT +: OUTBITS];
                           
//    two24_dsp #(.ABREG(1),
//                .CREG(0),
//		.PREG(0),
//	        .ALUMODE(`ALUMODE_Z_MINUS_XYCIN))
//                    sub_dsp(
//                    .clk_i(clk_i),
//                    .C_i({ add_total[1], add_total[0] }),
//                    .AB_i( { {8{1'b0}}, sq_sum_store[1][12], {8{1'b0}}, sq_sum_store[0][12] }), //12*4 samples sets = 48s (32ns at 1.5GHZ) 
//                    .P_o( {running_total[1], running_total[0]} ));
    
endmodule
