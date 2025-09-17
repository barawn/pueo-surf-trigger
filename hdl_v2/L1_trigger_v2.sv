`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1
module L1_trigger_v2 #(parameter NBEAMS=2, 
                       parameter TRIGGER_TYPE = "V3",
                       parameter WBCLKTYPE = "NONE", 
                       parameter CLKTYPE = "NONE",
                       parameter IFCLKTYPE = "NONE",
                       localparam NCHAN=8,
                       localparam NSAMP=(TRIGGER_TYPE=="LF" ? 4 : 8),
                       localparam AGC_BITS=5)(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),

        input tclk,
        input [NCHAN-1:0][AGC_BITS*NSAMP-1:0] dat_i,
        
        input aclk,
        input aclk_phase_i,
        input ifclk,
        output [NBEAMS-1:0] trigger_o,
        output trigger_count_done_o
    );

    localparam OPTIMIZED = "TRUE";    
    localparam ZERO_IS_FAKE = (NBEAMS == 2) ? "TRUE" : "FALSE";

    // OK - the L1 space consists of the thresholds
    // and scalers. We split them up here, but mangle
    // the addresses to match the old version.
    
    // In the global levelone space, these are:
    // 0x0000 - 0x03FF      (reserved)
    // 0x0400 - 0x05FF      (scalers)
    // 0x0600 - 0x07FF      (subthreshold scalers)
    // 0x0800 - 0x09FF      (thresholds)
    // 0x0a00 - 0x0bff      (subthresholds)
    // 0x0c00 - 0x0fff      (reserved)
    // 0x1000 - 0x17ff      (reserved)
    // 0x1800 - 0x1fff      (threshold/scal control)
    `DEFINE_WB_IF( thresh_ , 12, 32 );
    `DEFINE_WB_IF( scaler_ , 12, 32 );

    assign thresh_cyc_o = wb_cyc_i && wb_adr_i[11];
    assign thresh_stb_o = thresh_cyc_o;
    assign thresh_we_o = wb_we_i;
    assign thresh_dat_o = wb_dat_i;
    assign thresh_adr_o = { wb_adr_i[12],wb_adr_i[10:0] };
    assign thresh_sel_o = wb_sel_i;
    
    assign scaler_cyc_o = wb_cyc_i && !wb_adr_i[11];
    assign scaler_stb_o = scaler_cyc_o;
    assign scaler_we_o = wb_we_i;
    assign scaler_dat_o = wb_dat_i;
    assign scaler_adr_o = { wb_adr_i[12],wb_adr_i[10:0] };
    assign scaler_sel_o = wb_sel_i;
    
    assign wb_ack_o = (wb_adr_i[11]) ? thresh_ack_i : scaler_ack_i;
    assign wb_dat_o = (wb_adr_i[11]) ? thresh_dat_i : scaler_dat_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    
    wire scal_bank;     //! current active scaler bank (for debug/sync)
    wire scal_timer;    //! scaler measure period is over
    wire scal_rst;      //! force scaler update process into reset
    
    wire [18*2-1:0] thresh_dat; //! threshold setting bus
    wire [1:0] thresh_wr;       //! threshold write (shift up cascade bus)
    wire [1:0] thresh_update;   //! update all thresholds
    
    wire [1:0][NBEAMS-1:0] triggers;   //! both the real and subthresholds
                                       //! 0 = real
                                       //! 1 = subthreshold
    wire [1:0][NBEAMS-1:0] trig_stretch;
                                           
    // this can be aclk.
    wb_thresholds #(.NBEAMS(NBEAMS),
                    .WBCLKTYPE(WBCLKTYPE),
                    .ACLKTYPE(CLKTYPE))
        u_thresh_wb( .wb_clk_i(wb_clk_i),
                     `CONNECT_WBS_IFM( wb_ , thresh_ ),
                     .scal_bank_i(scal_bank),
                     .scal_timer_o(scal_timer),
                     .scal_rst_o(scal_rst),
                     .aclk(aclk),
                     .thresh_o(thresh_dat),
                     .thresh_wr_o(thresh_wr),
                     .thresh_update_o(thresh_update));
    
    // this MUST be tclk
    generate
        if (TRIGGER_TYPE == "LF") begin : LF
            beamform_trigger_lowampa #(.NBEAMS(NBEAMS))
                u_beam_trigger( .clk_i(tclk),
                                .data_i(dat_i),
                                .thresh_i(thresh_dat),
                                .thresh_wr_i(thresh_wr),
                                .thresh_update_i(thresh_update),
                                .trigger_o(triggers));
        end
        else if (TRIGGER_TYPE == "V3") begin : O3
            beamform_trigger_v3 #(.FULL(NBEAMS == 2 ? "FALSE" : "TRUE"),
                                  .DEBUG(NBEAMS == 2 ? "TRUE" : "FALSE"))
                u_beam_trigger( .clk_i(tclk),
                                .data_i(dat_i),
                                .thresh_i(thresh_dat),
                                .thresh_wr_i(thresh_wr),
                                .thresh_update_i(thresh_update),
                                .trigger_o(triggers));
        end
        else begin : V2
            if (OPTIMIZED == "TRUE") begin : O
                beamform_trigger_v2b #(.FULL(NBEAMS == 2 ? "FALSE" : "TRUE"),
                                       .DEBUG(NBEAMS == 2 ? "TRUE" : "FALSE"))
                    u_beam_trigger( .clk_i(tclk),
                                    .data_i(dat_i),
                                    .thresh_i(thresh_dat),
                                    .thresh_wr_i(thresh_wr),
                                    .thresh_update_i(thresh_update),
                                    .trigger_o(triggers));
            end else begin : N
                beamform_trigger_v2 #(.NBEAMS(NBEAMS),
                                      .ZERO_IS_FAKE(ZERO_IS_FAKE))
                    u_beam_trigger( .clk_i(tclk),
                                    .data_i(dat_i),
                                    .thresh_i(thresh_dat),
                                    .thresh_wr_i(thresh_wr),
                                    .thresh_update_i(thresh_update),
                                    .trigger_o(triggers));
            end
        end                        
    endgenerate
    // Now we want to cross the triggers from aclk -> ifclk.
    // This is an old module we reuse, hence NBEAMS*2 to cover
    // the subthresholds.
    //
    // We can exit tclk here.
    trig_cc_stretch #(.NBEAMS(NBEAMS*2))
        u_stretch(.aclk(aclk),
                  .aclk_phase_i(aclk_phase_i),
                  .trig_i(triggers),
                  .ifclk(ifclk),
                  .trig_o(trig_stretch));

    assign trigger_o = trig_stretch[0];

    beamscaler_wb_wrap #(.NBEAMS(NBEAMS),
                         .DEBUG("TRUE"),
                         .IFCLKTYPE(IFCLKTYPE),
                         .WBCLKTYPE(WBCLKTYPE))
        u_scalers(.wb_clk_i(wb_clk_i),
                  `CONNECT_WBS_IFM(wb_ , scaler_ ),
                  
                  .ifclk_i(ifclk),
                  .count_i(trig_stretch),
                  .timer_i(scal_timer),
                  .done_o(trigger_count_done_o),
                  .bank_o(scal_bank),
                  .rst_i(scal_rst));

endmodule
