`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Generate 4 of the metadata outputs for the beams.
// This module generates 4x22-way reductive OR using DSP adders.
// For the PUEO beams, none of our inputs are actually over 12 bits,
// but this module allows for up to 22.
//
// This module takes in the MASKED beam outputs which are generated
// by the first trigger DSP, otherwise masked beams would screw 
// with the metadata.
module beam_meta_nybble(
        input clk_i,
        input [21:0] bit0_i,
        input [21:0] bit1_i,
        input [21:0] bit2_i,
        input [21:0] bit3_i,
        output [3:0] meta_o
    );
    
    wire [47:0] dsp_AB;
    wire [47:0] dsp_C;
    
    assign dsp_AB = { 1'b0, bit3_i[0 +: 11],
                      1'b0, bit2_i[0 +: 11],
                      1'b0, bit1_i[0 +: 11],
                      1'b0, bit0_i[0 +: 11] };
    assign dsp_C  = { 1'b0, bit3_i[11 +: 11],
                      1'b0, bit2_i[11 +: 11],
                      1'b0, bit1_i[11 +: 11],
                      1'b0, bit0_i[11 +: 11] };
    
    // reset and CE usage is by default 0,
    // ABREG/CREG/PREG are all 1 so the overall latency
    // is 2 clocks.
    // The way this works is we add AB + C + RND and look for carry,
    // where RND is 0xFFFF. We need to make sure we don't go *past* the carry
    // so we're limited to 11 bits for each input since 0x7FF+0x7FF+0xFFF is
    // 0x1FFD.
    four12_dsp #(.RND({48{1'b1}}),
                 .OPMODE( { `W_OPMODE_RND, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB } ))
        u_dsp(.clk_i(clk_i),
              .AB_i(dsp_AB),
              .C_i(dsp_C),
              .CARRY_o(meta_o));
              
endmodule
