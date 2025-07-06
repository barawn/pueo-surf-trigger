`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1
module L1_trigger_v2 #(parameter NBEAMS=2, 
                       parameter WBCLKTYPE = "NONE", 
                       parameter CLKTYPE = "NONE",
                       parameter [31:0] TARGET_DEFAULT = 32'h0,
                       parameter [15:0] DELTA_DEFAULT = 16'h0,
                       parameter [47:0] TRIGGER_CLOCKS=375000000,
                       parameter HOLDOFF_CLOCKS=16,
                       localparam NCHAN=8,
                       localparam NSAMP=8,
                       localparam AGC_BITS=5)(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),

        output [47:0] mask_o,
        output [1:0] mask_wr_o,
        output mask_update_o,
        output mask_rst_o,
        
        input tclk,        
        input [NCHAN-1:0][AGC_BITS*NSAMP-1:0] dat_i,
        
        input aclk,
        input aclk_phase_i,
        input ifclk,
        output [NBEAMS-1:0] trigger_o,
        output trigger_count_done_o
    );

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
                            
                            .mask_o(mask_o),
                            .mask_wr_o(mask_wr_o),
                            .mask_update_o(mask_update_o),
                            .mask_rst_o(mask_reset_o),
                            
                            .first_reset_o(first_reset),
                            .agc_reset_o(agc_reset));

    // note: tclk's clktype is the same as aclk since they're
    // exactly the same clock, just off early on.

    // these trigger signals are in ifclk
    // signals from the loop controller
    wire [17:0] loop_thresh;
    wire [NBEAMS-1:0] loop_thresh_ce;
    wire loop_update;
    
    beamform_trigger_wrap #(.NBEAMS(NBEAMS),
                            .WBCLKTYPE(WBCLKTYPE),
                            .CLKTYPE(CLKTYPE))
        u_trigger( .tclk(tclk),
                   .data_i(dat_i),
                   
                   .thresh_i(loop_thresh),
                   .thresh_ce_i(loop_thresh_ce),
                   .update_i(loop_update),
                   
                   .aclk(aclk),
                   .aclk_phase_i(aclk_phase_i),
                   .ifclk(ifclk),
                   .trigger_o(trigger_o));
    
endmodule
