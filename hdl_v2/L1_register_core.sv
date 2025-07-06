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

        input [31:0] scal_dat_i,
        output [5:0] beam_idx_o,

        input [17:0] thresh_dat_i,
        output [17:0] thresh_dat_o,
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

    localparam [12:0] SCALER_BASE       = 13'h0400;    
    localparam [12:0] THRESHOLD_BASE    = 13'h0800;
         
    // shadow for params
    localparam [12:0] PARAM_MASK = 13'h03F8;
    // shadow for control
    localparam [12:0] CONTROL_MASK = 13'h0FF0;
    // scaler space
    localparam [12:0] SCALER_MASK = 13'h03FF;
    // threshold space
    localparam [12:0] THRESHOLD_MASK = 13'h07FF;
    
    `ifdef ADDR_MATCH
    `undef ADDR_MATCH
    `endif
    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
        
    // the first space is basically parameters 
    wire [1:0] submodule = wb_adr_i[11:10];
    wire [31:0] submodule_data[3:0];

    wire [31:0] parameter_data[1:0];
    wire [31:0] threshold_data;
    wire [31:0] control_data[3:0];

    assign submodule_data[0] = wb_adr_i[9] ? scal_dat_i : parameter_data[wb_adr_i[2]];
    assign submodule_data[1] = { {14{1'b0}}, thresh_dat_i };
    assign submodule_data[2] = control_data[wb_adr_i[3:2]];
    assign submodule_data[3] = submodule_data[1];
    
    reg [5:0] beam_idx = {16{1'b0}};
    
    reg [31:0] target_rate = TARGET_DEFAULT;
    reg [15:0] target_delta = DELTA_DEFAULT;
    
    assign parameter_data[0] = { {16{1'b0}}, target_delta };
    assign parameter_data[1] = target_rate;
    
    reg loop_enable = 0;
    reg [1:0] loop_state_req = {2{1'b0}};
    reg thresh_update = 0;
    reg thresh_wr = 0;
    reg [17:0] thresh_hold = {18{1'b0}};
    
    reg [47:0] mask = {48{1'b0}};
    reg [1:0] mask_wr = {2{1'b0}};
    reg mask_update = 0;
    
    reg first_reset = 0;
    reg agc_reset = 0;
    reg mask_reset = 0;

    assign control_data[0] = { {7{1'b0}}, thresh_update,
                               {7{1'b0}}, reset_complete_i,
                               {6{1'b0}}, loop_state_i,
                               {6{1'b0}}, loop_state_req };
    assign control_data[1] = { {28{1'b0}},
                               loop_enable,
                               mask_reset,
                               agc_reset,
                               first_reset };
    assign control_data[2] = { {14{1'b0}}, mask[17:0] };
    assign control_data[3] = { {2{1'b0}}, mask[18 +: 30] }; 
           
    reg [31:0] dat_mux = {32{1'b0}};

    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] TRANSACTION = 1;
    localparam [FSM_BITS-1:0] THRESH_WAIT = 2;
    localparam [FSM_BITS-1:0] THRESH_UPDATE = 3;
    localparam [FSM_BITS-1:0] ACK = 4;
    reg [FSM_BITS-1:0] state = IDLE;
        
    always @(posedge wb_clk_i) begin
        if (wb_cyc_i && wb_stb_i)
            beam_idx <= wb_adr_i[2 +: 5];
            
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) state <= TRANSACTION;
            TRANSACTION: if (`ADDR_MATCH(wb_adr_i, THRESHOLD_BASE, THRESHOLD_MASK))
                            state <= THRESH_WAIT;
                         else
                            state <= ACK;
            THRESH_WAIT: if (thresh_ack_i) begin
                            if (thresh_update) state <= THRESH_UPDATE;
                            else state <= ACK;
                         end
            THRESH_UPDATE: if (thresh_ack_i) state <= ACK;
            ACK: state <= IDLE;
        endcase            
            
        // masks have to propagate a wr...
        mask_wr[0] <= (state == TRANSACTION && wb_we_i && 
                       `ADDR_MATCH(wb_adr_i, MASK_A_ADDR, CONTROL_MASK));
        mask_wr[1] <= (state == TRANSACTION && wb_we_i &&
                       `ADDR_MATCH(wb_adr_i, MASK_A_ADDR, CONTROL_MASK));
        mask_update <= (state == ACK && |mask_wr && wb_dat_i[31]);
        
        if (state == TRANSACTION && wb_we_i) begin
            if (`ADDR_MATCH( wb_adr_i, DELTA_ADDR, PARAM_MASK)) begin
                target_delta <= wb_dat_i[15:0];
            end
            if (`ADDR_MATCH( wb_adr_i, TARGET_ADDR, PARAM_MASK)) begin
                target_rate <= wb_dat_i;
            end
            if (`ADDR_MATCH( wb_adr_i, LOOPSTATE_ADDR, CONTROL_MASK)) begin
                loop_state_req <= wb_dat_i[1:0];
            end
            if (`ADDR_MATCH( wb_adr_i, RESET_ADDR, CONTROL_MASK)) begin
                first_reset <= wb_dat_i[0];
                agc_reset <= wb_dat_i[1];
                mask_reset <= wb_dat_i[2];
                loop_enable <= wb_dat_i[3];
            end
            if (`ADDR_MATCH( wb_adr_i, MASK_A_ADDR, CONTROL_MASK)) begin
                mask[0 +: 18] <= wb_dat_i[0 +: 18];
            end
            if (`ADDR_MATCH( wb_adr_i, MASK_B_ADDR, CONTROL_MASK)) begin
                mask[18 +: 30] <= wb_dat_i[18 +: 30];                
            end
            if (`ADDR_MATCH( wb_adr_i, THRESHOLD_BASE, THRESHOLD_MASK)) begin
                thresh_hold <= wb_dat_i[0 +: 18];
                thresh_update <= wb_dat_i[31];
            end            
        end
    end
    
    assign target_rate_o = target_rate;
    assign target_delta_o = target_delta;
    
    assign first_reset_o = first_reset;
    assign agc_reset_o = agc_reset;
    
    assign loop_state_req_o = loop_state_req;
    assign loop_enable_o = loop_enable;
    
    assign mask_o = mask;
    assign mask_wr_o = mask_wr;
    assign mask_rst_o = mask_reset;

    assign thresh_dat_o = thresh_hold;
    assign thresh_wr_o = (state == THRESH_WAIT);
    assign thresh_update_o = (state == THRESH_UPDATE);
    
    `undef ADDR_MATCH
endmodule