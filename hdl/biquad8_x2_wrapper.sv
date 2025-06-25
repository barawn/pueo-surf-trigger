`timescale 1ns / 1ps
`include "interfaces.vh"

// Two biquads in serial, with coefficients loaded in by wishbone interface
// TODO Make Fixed point parameterizable
module biquad8_x2_wrapper(
        input wb_clk_i,
        input wb_rst_i,
                                                    // Using [7:2] of address space
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 8, 32 ),  // Address width, data width    
        input reset_BQ_i,
        input aclk,
        input [95:0] dat_i,
        
        output [95:0] dat_o
    );

    // // UNPACK is 128 -> 96
    // function [95:0] unpack;
    //     input [127:0] data_in;
    //     integer i;
    //     begin
    //         for (i=0;i<8;i=i+1) begin
    //             unpack[12*i +: 12] = data_in[(16*i+4) +: 12];
    //         end
    //     end
    // endfunction
    // // PACK is 96 -> 128
    // function [127:0] pack;
    //     input [95:0] data_in;
    //     integer i;
    //     begin
    //         for (i=0;i<8;i=i+1) begin
    //             pack[(16*i+4) +: 12] = data_in[12*i +: 12];
    //             pack[(16*i) +: 4] = {4{1'b0}};
    //         end
    //     end
    // endfunction    
    
    // Wishbone connection for loading Biquad coeffs 
    `DEFINE_WB_IF( bq0_ , 7, 32);
    `DEFINE_WB_IF( bq1_ , 7, 32);
    // stupidest intercon ever
    assign wb_ack_o = (wb_adr_i[7]) ? bq1_ack_i : bq0_ack_i;
    assign wb_err_o = (wb_adr_i[7]) ? bq1_err_i : bq0_err_i;
    assign wb_rty_o = (wb_adr_i[7]) ? bq1_rty_i : bq0_rty_i;
    assign wb_dat_o = (wb_adr_i[7]) ? bq1_dat_i : bq0_dat_i;
    
    assign bq0_cyc_o = wb_cyc_i && !wb_adr_i[7];
    assign bq1_cyc_o = wb_cyc_i && wb_adr_i[7];
    assign bq0_stb_o = wb_stb_i;
    assign bq1_stb_o = wb_stb_i;
    assign bq0_adr_o = wb_adr_i[6:0];
    assign bq1_adr_o = wb_adr_i[6:0];
    assign bq0_dat_o = wb_dat_i;
    assign bq1_dat_o = wb_dat_i;
    assign bq0_we_o = wb_we_i;
    assign bq1_we_o = wb_we_i;
    assign bq0_sel_o = wb_sel_i;
    assign bq1_sel_o = wb_sel_i;
    

    // these are the outputs
    wire [95:0] bq_out[1:0];
    assign dat_o = bq_out[1];
    
    
    biquad8_wrapper #(.NBITS(12),
                      .NFRAC(0),
                      .NSAMP(8),
                      .OUTBITS(12),
                      .OUTFRAC(0),
                      .WBCLKTYPE("PSCLK"),
                      .CLKTYPE("ACLK"))
        u_biquad8_A(.wb_clk_i(wb_clk_i),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM( wb_ , bq0_ ),
                  .clk_i(aclk),
                  .rst_i(reset_BQ_i),
                  .global_update_i(1'b0),
                  .dat_i(dat_i),
                  .dat_o(bq_out[0]));   

    biquad8_wrapper #(.NBITS(12),
                      .NFRAC(0),
                      .NSAMP(8),
                      .OUTBITS(12),
                      .OUTFRAC(0),
                      .WBCLKTYPE("PSCLK"),
                      .CLKTYPE("ACLK"))
        u_biquad8_B(.wb_clk_i(wb_clk_i),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM( wb_ , bq1_ ),
                  .clk_i(aclk),
                  .rst_i(reset_BQ_i),
                  .global_update_i(1'b0),
                  .dat_i(bq_out[0]),
                  .dat_o(bq_out[1]));   

endmodule
