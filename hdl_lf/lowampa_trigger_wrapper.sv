`timescale 1ns / 1ps
`include "interfaces.vh"
`include "debug_enable.vh"

`define DLYFF #0.1

module lowampa_trigger_wrapper #(parameter NBEAMS=48, 
                    parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter AGC_CONTROL = "TRUE",
                    parameter USE_BIQUADS = "FALSE",
                    parameter WBCLKTYPE = "NONE",
                    parameter CLKTYPE = "NONE",
                    parameter IFCLKTYPE = "NONE",
                    localparam DAT_WIDTH=96,
                    localparam NCHAN=8)( 

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ), // Address width, data width.

        input aclk,
        input aclk_phase_i,
        
        input tclk,
        input [NCHAN-1:0][DAT_WIDTH-1:0] dat_i,
        
        input ifclk,
        input ifclk_running_i,
        input runrst_i,
        input runstop_i,

        `HOST_NAMED_PORTS_AXI4S_MIN_IF(m_trig_ , 32),
        output [3:0][1:0][47:0] dat_debug,
        output [255:0] debug_envelope
    );
    
    localparam AGC_BITS = 5;
    localparam NSAMPS=4;

    // our submodules 
   `DEFINE_WB_IF( thresh_ , 13, 32 );
   `DEFINE_WB_IF( generator_ , 13, 32 );
   `DEFINE_WB_IF( agc_ , 13, 32 );
   `DEFINE_WB_IF( bq_ , 13, 32 );
    
    // post-AGC data
    wire  [NCHAN-1:0][AGC_BITS*NSAMPS-1:0] data_stage_connection;
            
    // triggers
    wire [NBEAMS-1:0] triggers;    
    wire trig_count_done;
   
//    // and make 'em
//    L1_trigger_intercon u_intercon(.wb_clk_i(wb_clk_i),
//             .clock_enabled_i( ifclk_running_i ),
//			 `CONNECT_WBS_IFS( wb_ , wb_ ),
//			 `CONNECT_WBM_IFM( thresh_ , thresh_ ),
//			 `CONNECT_WBM_IFM( control_ , generator_ ),
//			 `CONNECT_WBM_IFM( agc_ , agc_ ),
//			 `CONNECT_WBM_IFM( bq_ , bq_ ));


    // this is the threshold space
    lowampa_trigger #(.NBEAMS(NBEAMS),
                    .WBCLKTYPE(WBCLKTYPE),
                    .CLKTYPE(CLKTYPE),
                    .IFCLKTYPE(IFCLKTYPE))
        u_trigger(.wb_clk_i(wb_clk_i),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM( wb_ , thresh_ ),
                  
                  .tclk(tclk),
                  .dat_i(data_stage_connection),
                  
                  .aclk(aclk),
                  .aclk_phase_i(aclk_phase_i),
                  .ifclk(ifclk),
                  .trigger_count_done_o(trig_count_done),
                  .debug_envelope(debug_envelope),
                  .trigger_o(triggers));   
                  
    // this is the AGC and biquad space, and most of the trigger
    // chain.
    // For now the AGC reset stuff is pulled from the generator.
    wire agc_reset;
    lowampa_trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS),
                           .AGC_CONTROL(AGC_CONTROL),
                           .USE_BIQUADS(USE_BIQUADS),
                           .WBCLKTYPE(WBCLKTYPE),.CLKTYPE(CLKTYPE))
            u_chain(
                .wb_clk_i(wb_clk_i),
                .wb_rst_i(wb_rst_i),
                `CONNECT_WBS_IFM( wb_bq_ , bq_ ),//L
                `CONNECT_WBS_IFM( wb_agc_ , agc_ ),
                .reset_i(1'b0), 
                .agc_reset_i(1'b0),
                .aclk(aclk),
                .aclk_phase_i(aclk_phase_i),
                .dat_i(dat_i),
                .dat_o(data_stage_connection),
                .dat_debug(dat_debug));
      
    // finally this is the generator space, which in V2 is embedded
    // in the trigger module.   
    // this also contains the AGC reset for no particularly good reason
//    generator_wrap #(.WBCLKTYPE(WBCLKTYPE),
//                     .IFCLKTYPE(IFCLKTYPE),
//                     .NBEAMS(NBEAMS))
//        u_generator( .wb_clk_i(wb_clk_i),
//                     `CONNECT_WBS_IFM( wb_ , generator_ ),
//                     .agc_reset_o(agc_reset),
//                     .ifclk(ifclk),
//                     .ifclk_running_i(ifclk_running_i),
//                     .trig_i(triggers),                     
//                     .runrst_i(runrst_i),
//                     .runstop_i(runstop_i),
//                     `CONNECT_AXI4S_MIN_IF( trig_, m_trig_ ));                              
   
endmodule
