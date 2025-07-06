`timescale 1ns / 1ps
`include "interfaces.vh"
module L1_register_core #(parameter WBCLKTYPE="NONE",
                          parameter [31:0] TARGET_DEFAULT = 100,
                          parameter [15:0] DELTA_DEFAULT = 5)(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        
        output loop_enable_o,
        input reset_complete_i,
        output [1:0] loop_state_req_o,
        input [1:0] loop_state_i,

        output [31:0] target_rate_o,
        output [15:0] target_delta_o,

        input [31:0] scal_data_i,
        output [5:0] beam_idx_o,

        input [31:0] thresh_data_i,
        output thresh_update_o,
        output thresh_wr_o,
        input thresh_ack_i,

        output [47:0] mask_o,
        output [1:0] mask_wr_o,
        output mask_update_o,
        output mask_rst_o,

        output first_reset_o,
        output agc_reset_o                
    );

    localparam [12:0] DELTA_ADDR        = 13'h0000;
    localparam [12:0] TARGET_ADDR       = 13'h0004;
    // scalers get      0400-07FF
    // thresholds get   0800-0FFF 
    localparam [12:0] LOOPSTATE_ADDR    = 13'h1000;
    localparam [12:0] RESET_ADDR        = 13'h1004;
    localparam [12:0] MASK_A_ADDR       = 13'h1008;
    localparam [12:0] MASK_B_ADDR       = 13'h100C;
         
    // the first space is basically parameters but 
    wire [1:0] submodule = wb_adr_i[11:10];
    wire [31:0] submodule_data[3:0];

    wire [31:0] scaler_data;
    wire [31:0] parameter_data;
    wire [31:0] threshold_data;
    wire [31:0] control_data[3:0];

    assign submodule_data[0] = wb_adr_i[9] ? scaler_data : parameter_data;
    assign submodule_data[1] = threshold_data;
    assign submodule_data[2] = control_data[wb_adr_i[3:2]];
    assign submodule_data[3] = submodule_data[1];
    
    reg [31:0] target_rate = {32{1'b0}};
    reg [15:0] target_delta = {16{1'b0}};
    
    reg loop_enable = 0;
    reg [1:0] loop_state_req = {2{1'b0}};
    reg thresh_update = 0;
    reg thresh_wr = 0;
    reg [17:0] thresh_hold = {18{1'b0}};
    
    reg [47:0] mask = {48{1'b0}};
    reg [1:0] mask_wr = {2{1'b0}};
    reg mask_preupdate = 0;
    reg mask_update = 0;
    
    reg first_reset = 0;
    reg agc_reset = 0;
    reg mask_reset = 0;

    assign control_data[0] = { {7{1'b0}}, reset_complete_i,
                               {7{1'b0}}, loop_enable,
                               {6{1'b0}}, loop_state_i,
                               {6{1'b0}}, loop_state_req };
    assign control_data[1] = { {29{1'b0}},
                               mask_reset,
                               agc_reset,
                               first_reset };
    assign control_data[2] = { {14{1'b0}}, mask[17:0] };
    assign control_data[3] = { {2{1'b0}}, mask[18 +: 30] }; 
           
    reg [31:0] dat_mux = {32{1'b0}};

    always @(posedge wb_clk_i) begin
            
    end    
    
endmodule
