`timescale 1ns / 1ps
// agc dsp
`include "dsp_macros.vh"
// ok so this is a bit complicated:
// Scale is *always* 17 bits (the max).
// Q_SCALE sets the fractional part (represent scale_i = scale * 2^(Q_SCALE))
// Q_OFFSET sets the fractional part of the offset (represent offset_i = offset * 2^(Q_OFFSET))
//
// We need to align data and offset (MAX(Q_DAT, Q_OFFSET))
// scale up, and then shift the number of fractional bits. 
// so finally the LSB location is
// (Q_DAT > Q_OFFSET) ? Q_DAT+Q_SCALE+SCALE_IN-NFRAC_OUT : Q_OFFSET+Q_SCALE+SCALE_IN-NFRAC_OUT
// with Q_SCALE = 12 (scale_i = scale*4096)
//      Q_DAT = 0    (dat = dat_i)
//      Q_OFFSET = 8 (offset_i = offset*256)
//      SCALE_IN = 5 (input scale RMS is 32)
//      NFRAC_OUT = 2  (want 2 bits below RMS)
// 12+8+5-2 = 23
// 

// NOTE NOTE NOTE NOTE NOTE NOTE:
//
// The one thing we need to note here is DATA MUST GO IN THE D PATH
// This gives us 2-deep register for BOTH the offset AND the scale
// which allows us to easily globally apply.
//
// B = scale
// A = offset
// D = data
//
// NOTE NOTE NOTE NOTE NOTE:
// Offset is 8-bit FIXED POINT SIGNED
// so if you put in "128" = 10000000
// then you're really putting in NEGATIVE 1
// AND YOU NEED TO DIVIDE BY 128, NOT 256
// I PROBABLY ALSO HAVE TO INCREASE THE RANGE OF THE OFFSET JUST A THOUGHT
//
// NO WAY WILL Q0.8 WORK
// GO CRAZY: Q8.8
// THIS MEANS Q_SUM WILL BE 8
// AND DESIRED LSB WILL BE 8 + 12 + 5 - 2 = 23
module agc_dsp #(parameter Q_SCALE = 12,
                 parameter DAT_BITS = 12,
                 parameter Q_DAT = 0,
                 parameter OFFSET_BITS=16,
                 parameter Q_OFFSET = 8,
                 parameter NBITS = 5,
                 parameter SCALE_IN = 5,
                 parameter NFRAC_OUT = 2,
                 parameter CLKTYPE = "NONE"
                 )(
        input clk_i,
        input [DAT_BITS-1:0] dat_i,
        input [16:0] scale_i,
        input [OFFSET_BITS-1:0] offset_i,
        input ce_scale_i,
        input ce_offset_i,
        input apply_i,
        
        output [NBITS-1:0] out_o,
        output [NBITS-2:0] abs_o,
        output gt_o,
        output lt_o    );

    // LOTS OF FIXED POINT TRACKING

    // We need to figure out which of the DAT or OFFSET have more fractional bits, and we choose the larger.
    localparam Q_SUM = (Q_DAT > Q_OFFSET) ? Q_DAT : Q_OFFSET;
    // SCALE_IN represents the power of 2 close to the RMS of the input: it's "nominal input scale" in RMS scaling
    // We then back up NFRAC_OUT bits to pick up the fraction.
    localparam DESIRED_LSB = Q_SUM + Q_SCALE + SCALE_IN - NFRAC_OUT;
        
    // mask off everything except the unsaturated bits
    // Saturation mask actually needs to be ONE LESS than the number of output bits
    // You are checking if the MSB (sign bit) in your output matches *all the other* bits above it
    localparam [47:0] SATURATION_MASK = { {(48-DESIRED_LSB-NBITS-1){1'b0}}, {(DESIRED_LSB+NBITS-1){1'b1}}};
    // saturation occurs if the pattern is NOT either all zeros or all ones
    localparam [47:0] SATURATION_PATTERN = {48{1'b0}};
    
    // this is Q12.8 feeding a 27-bit input
    // meaning we need to sign-extend 7 bits
    //                  3           7           12      8 
    // this is 27 bits in
    // we have DAT_BITS in
    // fundamentally we need 27 - DAT_BITS of padding
    // (Q_SUM-Q_DAT) happen on the bottom
    // so (27-DAT_BITS-(Q_SUM-Q_DAT)) sign-extension on top
    localparam DAT_PADDING = (Q_SUM-Q_DAT);
    localparam DAT_SIGNEXT = 27 - DAT_BITS - (Q_SUM-Q_DAT);
    wire [26:0] dsp_d = (DAT_PADDING > 0) ? { {DAT_SIGNEXT{dat_i[DAT_BITS-1]}}, 
                          dat_i, 
                          {DAT_PADDING{1'b0}}
                        } : { {DAT_SIGNEXT{dat_i[DAT_BITS-1]}}, dat_i };
    // this is Q8.8
    // OFF_PADDING will be 8-8 = 0
    // and OFF_SIGNEXT = 27-16- (8-8) = 11
    localparam OFF_PADDING = (Q_SUM-Q_OFFSET);
    localparam OFF_SIGNEXT = 27 - OFFSET_BITS - (Q_SUM - Q_OFFSET);
    wire [26:0] dsp_a = (OFF_PADDING > 0) ? { {OFF_SIGNEXT{offset_i[OFFSET_BITS-1]}},
                          offset_i,
                          {OFF_PADDING{1'b0}}
                          } : { {OFF_SIGNEXT{offset_i[OFFSET_BITS-1]}}, offset_i };                             
    // top 3 bits get dropped going into the preadder
    wire [29:0] dsp_a_full = { {3{1'b0}}, dsp_a };

    // scale *must* be positive so we forcibly prevent it from going negative.
    // its position also doesn't matter, it just affects the output locations
    wire [17:0] dsp_b = {1'b0, scale_i};
    
    // our opmodes are 00, Z_OPMODE_0, XY_OPMODE_M     
    wire [8:0] dsp_opmode = { 2'b00, `Z_OPMODE_0, `XY_OPMODE_M };
    // our ALUMODE is ALUMODE_SUM_ZXYCIN
    wire [3:0] dsp_alumode = `ALUMODE_SUM_ZXYCIN;
    // our INMODE is (A2+D)*B2 which is 0 0 1 0 0
    wire [4:0] dsp_inmode = 5'b00100;
    wire [47:0] dsp_p;
    wire patternmatch;
    wire patternbmatch;
    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(.AREG(2),.BREG(2),`C_UNUSED_ATTRS,.DREG(1),.ADREG(1),.MREG(1),
              .PREG(1),.USE_PATTERN_DETECT("PATDET"),
              .SEL_MASK("MASK"),
              .SEL_PATTERN("PATTERN"),
              .MASK(SATURATION_MASK),
              .PATTERN(SATURATION_PATTERN),
              .USE_MULT("MULTIPLY"),
              .AMULTSEL("AD"),
              `CONSTANT_MODE_ATTRS)
              u_dsp(.CLK(clk_i),
                    .A(dsp_a),
                    .B(dsp_b),
                    `C_UNUSED_PORTS,
                    .D(dsp_d),
                    .CEA2(apply_i),
                    .CEA1(ce_offset_i),
                    .CEB2(apply_i),
                    .CEB1(ce_scale_i),
                    .CED(1'b1),
                    .CEAD(1'b1),
                    .CEM(1'b1),
                    .CEP(1'b1),
                    
                    .INMODE(dsp_inmode),
                    .ALUMODE(dsp_alumode),
                    .OPMODE(dsp_opmode),
                    
                    .PATTERNDETECT(patternmatch),
                    .PATTERNBDETECT(patternbmatch),
                    .P(dsp_p));              

    saturate_and_scale #(.LSB(DESIRED_LSB))
        u_scale(.clk_i(clk_i),
                .in_i(dsp_p),
                .patternmatch_i(patternmatch),
                .patternbmatch_i(patternbmatch),
                .out_o(out_o),
                .abs_o(abs_o),
                .gt_o(gt_o),
                .lt_o(lt_o));

endmodule
