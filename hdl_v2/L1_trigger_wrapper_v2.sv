`timescale 1ns / 1ps
`include "interfaces.vh"
`include "debug_enable.vh"

`define DLYFF #0.1
`define STARTTHRESH 18'd4500

// v2. Try to more cleanly separate the loop and the outside WISHBONE bus.
module L1_trigger_wrapper_v2 #(parameter NBEAMS=2, 
                    parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter USE_BIQUADS = "FALSE",
                    parameter WBCLKTYPE = "NONE",
                    parameter CLKTYPE = "NONE",
                    parameter IFCLKTYPE = "NONE",
                    parameter [47:0] TRIGGER_CLOCKS=375000000*10,// at 375 MHz this will count for 10 seconds  
                    parameter HOLDOFF_CLOCKS=16,        // NOTE: Parameters are 32 bit max, which this exceeds
                    parameter STARTING_TARGET=100, // At 100 s period, this will be 1 Hz
                    parameter STARTING_DELTA=2,
                    parameter COUNT_MARGIN=10,
                    localparam DAT_WIDTH=96,
                    localparam NCHAN=8)( 

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ), // Address width, data width.

        input aclk,
        input [NCHAN-1:0][DAT_WIDTH-1:0] dat_i,
        
        input ifclk,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF(m_trig_ , 32)
    );
    
    localparam AGC_BITS = 5;
    localparam NSAMPS=8;
    localparam [31:0] TARGET_DEFAULT = 100;
    localparam [15:0] DELTA_DEFAULT = 5;

    // our submodules 
   `DEFINE_WB_IF( thresh_ , 13, 32 );
   `DEFINE_WB_IF( spare_ , 13, 32 );
   `DEFINE_WB_IF( agc_ , 13, 32 );
   `DEFINE_WB_IF( bq_ , 13, 32 );
   
    // and make 'em
    L1_trigger_intercon( .wb_clk_i(wb_clk_i),
			 `CONNECT_WBS_IFS( wb_ , wb_ ),
			 `CONNECT_WBM_IFM( thresh_ , thresh_ ),
			 `CONNECT_WBM_IFM( spare_ , spare_ ),
			 `CONNECT_WBM_IFM( agc_ , agc_ ),
			 `CONNECT_WBM_IFM( bq_ , bq_ ));

    wbs_dummy #(.ADDRESS_WIDTH(13),.DATA_WIDTH(32))
        u_dummy(`CONNECT_WBS_IFM( wb_ , spare_ ));

    // now we need a register core for the thresholds and generator.
    // interface to the L1
    // loop control
    wire loop_enable;
    wire reset_complete;
    wire [1:0] loop_state_req;
    wire [1:0] loop_state;
    // params
    wire [15:0] target_rate;
    wire [31:0] target_delta;
    // scaler data
    wire [31:0] scal_data;
    // beam index for both scalers and threshold
    wire [5:0]  beam_idx;
    // thresholds
    wire [17:0] new_thresh_dat;
    wire [17:0] thresh_dat;
    wire thresh_update;
    wire thresh_wr;
    wire thresh_ack;
    
    // I dunno about these two
    wire first_reset;
    wire agc_reset;
    // register core
    L1_register_core #(.WBCLKTYPE(WBCLKTYPE),
                       .TARGET_DEFAULT(TARGET_DEFAULT),
                       .DELTA_DEFAULT(DELTA_DEFAULT))
            u_levelone_regs(.wb_clk_i(wb_clk_i),
                            `CONNECT_WBS_IFM( wb_ , thresh_ ),
                            .loop_enable_o(loop_enable),
                            .reset_complete_i(reset_complete),
                            .loop_state_req_o(loop_state_req),
                            .loop_state_i(loop_state),
                            
                            .target_rate_o(target_rate),
                            .target_delta_o(target_delta),
                            
                            .scal_dat_i(scal_data),
                            .beam_idx_o(beam_idx),
                            
                            .thresh_dat_i(thresh_dat),
                            .thresh_dat_o(new_thresh_dat),
                            .thresh_update_o(thresh_update),
                            .thresh_wr_o(thresh_wr),
                            .thresh_ack_i(thresh_ack),
                            
                            .mask_o(mask),
                            .mask_wr_o(mask_wr),
                            .mask_update_o(mask_update),
                            .mask_rst_o(mask_reset),
                            
                            .first_reset_o(first_reset),
                            .agc_reset_o(agc_reset));
                                                   

    // trigger chain wrapper takes the agc and biquads    
    // AGC output over to the L1_trigger
    wire [NCHAN-1:0][AGC_BITS*NSAMPS-1:0] L1_data;
    // trigger to the generator
    wire [NBEAMS-1:0] trigger;
   
    trigger_chain_x8_wrapper
               #(   .WBCLKTYPE(WBCLKTYPE),
                    .CLKTYPE(CLKTYPE),
                    .AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS),
                    .USE_BIQUADS(USE_BIQUADS))
        u_chain_wrap( .wb_clk_i(wb_clk_i),
                      .wb_rst_i(wb_rst_i),
                      `CONNECT_WBS_IFM( wb_agc_ , agc_ ),
                      `CONNECT_WBS_IFM( wb_bq_ , bq_ ),
                      .reset_i(first_reset),
                      .agc_reset_i(agc_reset),                      
                      .aclk(aclk),
                      .dat_i(dat_i),
                      .dat_o(L1_data));
    
    // The L1 trigger now has the trigger chain factored out
    wire [47:0] mask;
    wire [1:0] mask_wr;
    wire mask_update;
    wire mask_reset;
    L1_trigger_v2 
               #(   .WBCLKTYPE(WBCLKTYPE),
                    .CLKTYPE(CLKTYPE),
                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS),
                    .NBEAMS(NBEAMS))
        u_L1_trigger(
            .wb_clk_i(wb_clk_i),
            .wb_rst_i(wb_rst_i),
            `CONNECT_WBS_IFM( wb_ , thresh_ ),
            
            .mask_o(mask),
            .mask_wr_o(mask_wr),
            .mask_update_o(mask_update),
            .mask_rst_o(mask_reset),
            
            .aclk(aclk),
            .dat_i(L1_data),
            
            .ifclk(ifclk),
            .trigger_o(trigger));

   // and now the trig gen
   
   
endmodule
