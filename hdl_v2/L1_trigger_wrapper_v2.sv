`timescale 1ns / 1ps
`include "interfaces.vh"
`include "debug_enable.vh"

`define DLYFF #0.1
// v2 module integration.
module L1_trigger_wrapper_v2 #(parameter NBEAMS=2, 
                    parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
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
   `DEFINE_WB_IF( generator_ , 13, 32 );
   `DEFINE_WB_IF( agc_ , 13, 32 );
   `DEFINE_WB_IF( bq_ , 13, 32 );
   
    // and make 'em
    L1_trigger_intercon( .wb_clk_i(wb_clk_i),
			 `CONNECT_WBS_IFS( wb_ , wb_ ),
			 `CONNECT_WBM_IFM( thresh_ , thresh_ ),
			 `CONNECT_WBM_IFM( generator_ , generator_ ),
			 `CONNECT_WBM_IFM( agc_ , agc_ ),
			 `CONNECT_WBM_IFM( bq_ , bq_ ));

    wbs_dummy #(.ADDRESS_WIDTH(13),.DATA_WIDTH(32))
        u_dummy(`CONNECT_WBS_IFM( wb_ , generator_ ));

   
   
endmodule
