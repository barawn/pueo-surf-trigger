`timescale 1ns / 1ps
`include "interfaces.vh"

// Check whether the bits selecting the channel match the value
`define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )

// 8 channels of trigger chain, with wisbone interconnect
module trigger_chain_x8_wrapper #(parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(  

        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 22, 32 ), // Address width, data width. Address is at size limit

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width. Address is at size limit
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i ,
        `ifdef USING_DEBUG
        output [7:0][1:0][95:0] dat_debug,
        `endif
        output [7:0][39:0] dat_o 
    );

    // QUALITY OF LIFE FUNCTIONS

    // UNPACK is 128 -> 96
    function [95:0] unpack;
        input [127:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                unpack[12*i +: 12] = data_in[(16*i+4) +: 12];
            end
        end
    endfunction
    // PACK is 96 -> 128
    function [127:0] pack;
        input [95:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                pack[(16*i+4) +: 12] = data_in[12*i +: 12];
                pack[(16*i) +: 4] = {4{1'b0}};
            end
        end
    endfunction    


    localparam [21:0] CHAN_MASK = 22'h1c00; //0001 1100 0000 0000

    // Connect the WB outputs
    wire [2:0] wb_bq_idx = wb_bq_adr_i[12:10];

    wire        wb_bq_ack_o_vec [7:0];
    wire        wb_bq_err_o_vec [7:0];
    wire        wb_bq_rty_o_vec [7:0];
    wire [31:0] wb_bq_dat_o_vec [7:0];

    assign wb_bq_ack_o = wb_bq_ack_o_vec[wb_bq_idx];
    assign wb_bq_err_o = wb_bq_err_o_vec[wb_bq_idx];
    assign wb_bq_rty_o = wb_bq_rty_o_vec[wb_bq_idx];
    assign wb_bq_dat_o = wb_bq_dat_o_vec[wb_bq_idx];
    
    
    wire [2:0] wb_agc_idx = wb_agc_adr_i[12:10];
    
    wire        wb_agc_ack_o_vec [7:0];
    wire        wb_agc_err_o_vec [7:0];
    wire        wb_agc_rty_o_vec [7:0];
    wire [31:0] wb_agc_dat_o_vec [7:0];

    assign wb_agc_ack_o = wb_agc_ack_o_vec[wb_agc_idx];
    assign wb_agc_err_o = wb_agc_err_o_vec[wb_agc_idx];
    assign wb_agc_rty_o = wb_agc_rty_o_vec[wb_agc_idx];
    assign wb_agc_dat_o = wb_agc_dat_o_vec[wb_agc_idx];


// ///// Actual WISHBONE definitions. These are the dumb WISHBONE
// ///// connections for now, I'll probably add a WBB3 or WBB4 or
// ///// whatever interface which tacks on the additional signals.
// `define DEFINE_WB_IFV( prefix , address_width, data_width, suffix ) \
//   wire [ data_width - 1:0] prefix``dat_i``suffix;                   \
//   wire [ data_width - 1:0] prefix``dat_o``suffix;                   \
//   wire [ address_width - 1:0] prefix``adr_o``suffix;                \
//   wire [ (data_width/8)-1:0] prefix``sel_o``suffix;                 \
//   wire prefix``cyc_o``suffix;                                       \
//   wire prefix``stb_o``suffix;                                       \
//   wire prefix``we_o``suffix;                                        \
//   wire prefix``ack_i``suffix;                                       \
//   wire prefix``rty_i``suffix;                                       \
//   wire prefix``err_i``suffix


    // Connect the AGC inputs
    genvar idx;
    generate
        for(idx = 0; idx<8; idx = idx+1) begin : TRIGGER_CHAIN_LOOP
            `DEFINE_WB_IF( wb_bq_connect_, 8, 32);
            `DEFINE_WB_IF( wb_agc_connect_, 8, 32);

            assign wb_bq_ack_o_vec[idx] = wb_bq_connect_ack_i;
            assign wb_bq_err_o_vec[idx] = wb_bq_connect_err_i;
            assign wb_bq_rty_o_vec[idx] = wb_bq_connect_rty_i;
            assign wb_bq_dat_o_vec[idx] = wb_bq_connect_dat_i;
            
            assign wb_agc_ack_o_vec[idx] = wb_agc_connect_ack_i;
            assign wb_agc_err_o_vec[idx] = wb_agc_connect_err_i;
            assign wb_agc_rty_o_vec[idx] = wb_agc_connect_rty_i;
            assign wb_agc_dat_o_vec[idx] = wb_agc_connect_dat_i;

            // The cyc signal controls whether anything happens
            assign wb_bq_connect_cyc_o = wb_bq_cyc_i && `ADDR_MATCH(wb_bq_adr_i, (idx * 12'h400), CHAN_MASK);
            assign wb_bq_connect_stb_o = wb_bq_stb_i;
            assign wb_bq_connect_adr_o = wb_bq_adr_i[7:0];
            assign wb_bq_connect_dat_o = wb_bq_dat_i;
            assign wb_bq_connect_we_o  = wb_bq_we_i;
            assign wb_bq_connect_sel_o = wb_bq_sel_i;


            // The cyc signal controls whether anything happens
            assign wb_agc_connect_cyc_o = wb_agc_cyc_i && `ADDR_MATCH(wb_agc_adr_i, (idx * 12'h400), CHAN_MASK);
            assign wb_agc_connect_stb_o = wb_agc_stb_i;
            assign wb_agc_connect_adr_o = wb_agc_adr_i[7:0];
            assign wb_agc_connect_dat_o = wb_agc_dat_i;
            assign wb_agc_connect_we_o  = wb_agc_we_i;
            assign wb_agc_connect_sel_o = wb_agc_sel_i;

            trigger_chain_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
            u_chain(
                .wb_clk_i(wb_clk_i),
                .wb_rst_i(wb_rst_i),
                `CONNECT_WBS_IFM( wb_bq_ , wb_bq_connect_ ),
                `CONNECT_WBS_IFM( wb_agc_controller_ , wb_agc_connect_ ),
                .reset_i(reset_i), 
                .aclk(aclk),
                .dat_i(dat_i[idx]),
                `ifdef USING_DEBUG
                    .dat_debug(dat_debug[idx]),
                `endif
                .dat_o(dat_o[idx]));
            end;
    endgenerate

    

endmodule

`undef ADDR_MATCH