`timescale 1ns / 1ps
`include "interfaces.vh"
module generator_wrap #(parameter WBCLKTYPE = "NONE",
                        parameter IFCLKTYPE = "NONE",
                        parameter USE_V3 = "FALSE",
                        parameter NBEAMS = 46)(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        output agc_reset_o, // this doesn't belong here but whatever
        input ifclk,
        input ifclk_running_i,
        input [NBEAMS-1:0] trig_i,
        input runrst_i,
        input runstop_i,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( trig_ , 32 )        
    );
    
    // need the nets from the WISHBONE core
    wire [47:0] beam_mask;
    wire [1:0] beam_wr;
    wire beam_update;
    
    wire gen_rst;
    generator_wb_core #(.WBCLKTYPE(WBCLKTYPE),
                        .IFCLKTYPE(IFCLKTYPE))
        u_wb(.wb_clk_i(wb_clk_i),
             `CONNECT_WBS_IFS(wb_, wb_),
             .ifclk(ifclk),
             .ifclk_running_i(ifclk_running_i),
             .agc_reset_o(agc_reset_o), // silliness
             .gen_rst_o(gen_rst),
             .beam_mask_o(beam_mask),
             .beam_mask_wr_o(beam_wr),
             .beam_mask_update_o(beam_update));                       

    // The v3 trig gen SHOULD be 'morphable' back into
    // the v2 with its parameter.
    surf_trig_gen_v3 #(.NBEAMS(NBEAMS),
                       .USE_V3(USE_V3),
                       .IFCLKTYPE(IFCLKTYPE),
                       .TRIG_CLOCKDOMAIN("IFCLK"))
        u_triggen(.ifclk(ifclk),
                  .trig_i(trig_i),
                  .mask_i(beam_mask),
                  .mask_wr_i(beam_wr),
                  .mask_update_i(beam_update),
                  .gen_rst_i(gen_rst),
                  .runrst_i(runrst_i),
                  .runstop_i(runstop_i),
                  `CONNECT_AXI4S_MIN_IF(trig_ , trig_ ));
                                          
endmodule
