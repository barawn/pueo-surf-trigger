`timescale 1ns / 1ps
`include "interfaces.vh"
module L1_trigger_loop_wrap #(parameter NBEAMS=2,
                              parameter WBCLKTYPE="NONE",
                              parameter CLKTYPE="NONE",
                              parameter [47:0] COUNT_CLOCKS = {48{1'b0}})(
        input wb_clk_i,
        // this is what takes us out of reset_start.
        input loop_enable_i,
        output reset_complete_o,
        
        // state change request interface
        input [1:0] loop_state_req_i,                       
        output [1:0] loop_state_o,
        
        input [31:0] target_rate_i,
        input [15:0] target_delta_i,
        
        // manual threshold update interface and readback
        input [17:0] thresh_dat_i,
        input [5:0] thresh_idx_i,
        // the ack here acks both of 'em
        input thresh_upd_i,
        input thresh_wr_i,
        output thresh_ack_o,
        output [17:0] thresh_dat_o,
        
        // scaler read interface
        input [5:0] scal_idx_i,
        output [31:0] scal_dat_o,
        
        output [17:0] thresh_o,
        output [NBEAMS-1:0] thresh_ce_o,
        output update_o,
                
        input ifclk,
        input [NBEAMS-1:0] trigger_i                        
    );
    
    `DEFINE_WB_IF( loop_ , 22, 32 );
    // okay we're just going to do this as immensely stupid as possible
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_WRITE = 1;
    localparam [FSM_BITS-1:0] WRITE_DONE = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg start_count_wbclk = 0;
    wire start_count_ifclk;
    flag_sync u_start_sync(.in_clkA(start_count_wbclk),.out_clkB(start_count_ifclk),
                           .clkA(wb_clk_i),.clkB(ifclk));
    reg [1:0] start_sequence = {2{1'b0}};
    reg counting_ifclk = 0;
    wire count_complete;
    wire count_complete_wbclk;
    reg count_finished = 0;
    always @(posedge wb_clk_i) begin
        if (loop_cyc_o && loop_stb_o && loop_we_o && loop_adr_o == {22{1'b0}} && loop_dat_o[0])
            count_finished <= 0;
        else if (count_complete_wbclk)
            count_finished <= 1;           
    end

    wire [NBEAMS-1:0] final_count[31:0];
    
    always @(posedge ifclk) begin
        start_sequence <= { start_sequence[0], start_count_ifclk };
        if (start_sequence[1]) counting_ifclk <= 1;
        else if (count_complete) counting_ifclk <= 0;        
    end
    
    wire stuck_ce;
    clk_div_ce #(.CLK_DIVIDE(31),
                 .EXTRA_DIV2("TRUE"))
                 u_stuck_timer(.clk(ifclk),
                               .ce(stuck_ce));
    
    generate
        genvar i;
        for (i=0;i<NBEAMS;i=i+1) begin : SC
            reg [31:0] beam_counter = {32{1'b0}};
            reg [1:0] trig_rereg = {2{1'b0}};
            reg [3:0] stuck_check = {4{1'b0}};
            reg count = 0;
            always @(posedge ifclk) begin : SCL
                trig_rereg <= { trig_rereg[0], trigger_i };
                if (!trig_rereg[0]) stuck_check <= {4{!'b0}};
                else stuck_check <= { stuck_check[2:0], trig_rereg[0] };
                
                count <= stuck_check[3] || (trig_rereg == 2'b01);
                
                // just... saturate at something big
                if (start_sequence[0]) 
                    beam_counter <= {32{1'b0}};
                else if (counting_ifclk && !beam_counter[31])
                    beam_counter <= beam_counter + count;                    
            end
            assign final_count[i] = beam_counter;
        end
    endgenerate

    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(COUNT_CLOCKS))
        u_timer(.clk_i(ifclk),
                .count_i(counting_ifclk),
                .tcount_reached_o(count_complete));

    
endmodule
