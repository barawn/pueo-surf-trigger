`timescale 1ns / 1ps

module beam_scalers #(parameter WBCLKTYPE = "NONE",
                      parameter CLKTYPE = "NONE",
                      parameter NBEAMS = 2)(
        input ifclk,
        input [NBEAMS-1:0] trigger_i
    );
    
        
    
endmodule

module beam_scaler_dsp #(parameter CASCADE = "FALSE")(
        input ifclk,
        input trig_i,
        input rst_i,
        input counting_i,
        input updating_i,
        input count_i,
        output [47:0] out_o,
        output [47:0] casc_o
        );

    // our magic here happens from the opmode
    // like, we are super-goddamn awesome folks

    // Carry. If we use a single DSP, this works because we're actually counting
    // (count_i)<<16
    wire carryout;
    // Capture if we cross the top bit, whatever it actually is, and hold that.
    // It flips our opmode Y input to {48{1'b1}} so we saturate.
    reg saturated = 0;
    
    

endmodule        