`timescale 1ns / 1ps
`include "interfaces.vh"
`include "debug_enable.vh"

`define DLYFF #0.1
// v2 module integration.
// Our space is split up into 4 subspaces:
// - threshold space (0x0000 - 0x1FFF)
// - generator space (0x2000 - 0x3FFF)
// - agc space       (0x4000 - 0x5FFF)
// - biquad space    (0x6000 - 0x7FFF)
module L1_trigger_wrapper_v2 #(parameter NBEAMS=2, 
                    parameter TRIGGER_TYPE = "V3",                    
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

        `HOST_NAMED_PORTS_AXI4S_MIN_IF(m_trig_ , 32)
    );
    
    localparam AGC_BITS = 5;
    localparam NSAMPS=(TRIGGER_TYPE == "LF") ? 4 : 8;

    localparam USE_V3 = (TRIGGER_TYPE == "V3" || TRIGGER_TYPE == "V31500") ?
        "TRUE" : "FALSE";
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
   
    // and make 'em
    L1_trigger_intercon u_intercon(.wb_clk_i(wb_clk_i),
             .clock_enabled_i( ifclk_running_i ),
			 `CONNECT_WBS_IFS( wb_ , wb_ ),
			 `CONNECT_WBM_IFM( thresh_ , thresh_ ),
			 `CONNECT_WBM_IFM( control_ , generator_ ),
			 `CONNECT_WBM_IFM( agc_ , agc_ ),
			 `CONNECT_WBM_IFM( bq_ , bq_ ));


    // this is the threshold space
    localparam L1TYPE = (TRIGGER_TYPE == "V31500") ? "V3" : TRIGGER_TYPE;
    L1_trigger_v2 #(.NBEAMS(NBEAMS),
                    .TRIGGER_TYPE(L1TYPE),
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
                  .trigger_o(triggers));   
                  
    // this is the AGC and biquad space, and most of the trigger
    // chain.
    // For now the AGC reset stuff is pulled from the generator.
    wire agc_reset;
    generate
        if (TRIGGER_TYPE == "LF") begin : LF
        
            wire [NCHAN-1:0][12*NSAMPS-1:0] dat_downsample;
            function [12*NSAMPS-1:0] downsample;
                    input [DAT_WIDTH-1:0] data_in;
                    begin
                        downsample = { data_in[6*12 +: 12],
                                       data_in[4*12 +: 12],
                                       data_in[2*12 +: 12],
                                       data_in[0*12 +: 12] };
                    end                                     
            endfunction
            
            assign dat_downsample[0] = downsample(dat_i[0]);
            assign dat_downsample[1] = downsample(dat_i[1]);
            assign dat_downsample[2] = downsample(dat_i[2]);
            assign dat_downsample[3] = downsample(dat_i[3]);
            assign dat_downsample[4] = downsample(dat_i[4]);
            assign dat_downsample[5] = downsample(dat_i[5]);
            assign dat_downsample[6] = downsample(dat_i[6]);
            assign dat_downsample[7] = downsample(dat_i[7]);
            
            // note note: this is an older wrapper, we should add the optional
            // AGC control elimination parameter. We also need to recheck the AGC
            // portion of this to make sure the syntax error stuff was cleaned up.
            lowampa_trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS),
                                               .AGC_CONTROL(AGC_CONTROL),
                                               .USE_BIQUADS(USE_BIQUADS),
                                               .WBCLKTYPE(WBCLKTYPE),
                                               .CLKTYPE(CLKTYPE))
                    u_chain(
                        .wb_clk_i(wb_clk_i),
                        .wb_rst_i(wb_rst_i),
                        `CONNECT_WBS_IFM( wb_bq_ , bq_ ),//L
                        `CONNECT_WBS_IFM( wb_agc_ , agc_ ),
                        .reset_i(1'b0), 
                        .agc_reset_i(agc_reset),
                        .aclk(tclk),
                        .aclk_phase_i(aclk_phase_i),
                        .dat_i(dat_downsample),
                        .dat_o(data_stage_connection));
        end else begin : MIE
            localparam CHAIN_TYPE = (TRIGGER_TYPE == "V31500") ? "HALF" : "FULL";
            trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS),
                                   .HDL_FILTER_VERSION("SYSTOLIC"),
                                   .AGC_CONTROL(AGC_CONTROL),
                                   .USE_BIQUADS(USE_BIQUADS),
                                   .CHAIN_TYPE(CHAIN_TYPE),
                                   .WBCLKTYPE(WBCLKTYPE),.CLKTYPE(CLKTYPE))
                    u_chain(
                        .wb_clk_i(wb_clk_i),
                        .wb_rst_i(wb_rst_i),
                        `CONNECT_WBS_IFM( wb_bq_ , bq_ ),//L
                        `CONNECT_WBS_IFM( wb_agc_ , agc_ ),
                        .reset_i(1'b0), 
                        .agc_reset_i(agc_reset),
                        .aclk(tclk),
                        .dat_i(dat_i),
                        .dat_o(data_stage_connection));
        end
    endgenerate        
              
    // finally this is the generator space, which in V2 is embedded
    // in the trigger module.   
    // this also contains the AGC reset for no particularly good reason
    // We also now pass USE_V3 as an option, which gets passed down to
    // the trigger generator and determines whether or not the beam metadata
    // is built.
    generator_wrap #(.WBCLKTYPE(WBCLKTYPE),
                     .IFCLKTYPE(IFCLKTYPE),
                     .USE_V3(USE_V3),
                     .NBEAMS(NBEAMS))
        u_generator( .wb_clk_i(wb_clk_i),
                     `CONNECT_WBS_IFM( wb_ , generator_ ),
                     .agc_reset_o(agc_reset),
                     .ifclk(ifclk),
                     .ifclk_running_i(ifclk_running_i),
                     .trig_i(triggers),                     
                     .runrst_i(runrst_i),
                     .runstop_i(runstop_i),
                     `CONNECT_AXI4S_MIN_IF( trig_, m_trig_ ));                              
   
endmodule
