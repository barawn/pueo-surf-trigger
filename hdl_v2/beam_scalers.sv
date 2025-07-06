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
        input counting_i,
        input updating_i,
        output [47:0] out_o,
        output [47:0] casc_o
        );

    

endmodule        