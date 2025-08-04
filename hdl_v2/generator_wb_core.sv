`timescale 1ns / 1ps
// this now has the beam masks
`include "interfaces.vh"
module generator_wb_core #(parameter WBCLKTYPE = "NONE",
                           parameter IFCLKTYPE = "NONE")(
        input wb_clk_i,
        input ifclk_running_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        input ifclk,
        output [47:0] beam_mask_o,
        output [1:0] beam_mask_wr_o,
        output beam_mask_update_o
    );
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [47:0] beam_mask = {48{1'b1}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [1:0] beam_wr = {2{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg beam_preupdate = 1'b0;
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg gen_rst = 0;

    reg beam_update = 1'b0;
    
    wire beam_write_wbclk;
    wire beam_write_busy_wbclk;
    wire beam_write_ifclk;
    
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg [1:0] beam_wr_ifclk = {2{1'b0}};
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg beam_preupdate_ifclk = 1'b0;    
    
    // The addresses here are spec'd in the global space and masked down
    // to their proper values.
    // Because we currently only have 4 registers, we shadow everything
    // as well and our mask is just 13'hF.    
    localparam [14:0] CONTROL_REG_0 = 15'h2000; // unused
    localparam [14:0] CONTROL_REG_1 = 15'h2004; // generator reset
    localparam [14:0] MASK_REG_0 =    15'h2008; // low 18 beams
    localparam [14:0] MASK_REG_1 =    15'h200C; // high 18 beams
            
    reg [31:0] wb_dat = {32{1'b0}};
    wire [31:0] wb_regs[3:0];
    assign wb_regs[0] = {32{1'b0}};
    assign wb_regs[1] = { {16{1'b0}}, {7{1'b0}}, gen_rst, {8{1'b0}} };
    assign wb_regs[2] = { {14{1'b0}}, beam_mask[0 +: 18] };
    assign wb_regs[3] = { {2{1'b0}}, beam_mask[18 +: 30] };
    
    `ifndef ADDR_MATCH    
    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    `endif
    
    // our writes are always cross-clock so we just need enough delay.
    // but we need to be clever.
    localparam FSM_BITS=3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] ISSUE_WRITE = 2;
    localparam [FSM_BITS-1:0] WRITE_WAIT_0 = 3;
    localparam [FSM_BITS-1:0] CAPTURE = 4;
    localparam [FSM_BITS-1:0] ACK = 5;
    reg [FSM_BITS-1:0] state = IDLE;
    
    always @(posedge wb_clk_i) begin        
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= CAPTURE;
            end 
            WRITE: if (wb_adr_i[3] && ifclk_running_i) state <= ISSUE_WRITE;
                   else state <= ACK;
            ISSUE_WRITE: state <= WRITE_WAIT_0;
            WRITE_WAIT_0: if (!beam_write_busy_wbclk) state <= ACK;
            CAPTURE: state <= ACK;
            ACK: state <= IDLE;
        endcase
        
        if (state == WRITE && `ADDR_MATCH(wb_adr_i, CONTROL_REG_1, 13'hF)) begin
            gen_rst <= wb_dat_i[8];
        end
        
        if (state == CAPTURE) wb_dat <= wb_regs[wb_adr_i[3:2]];
        
        if (state == ACK) begin
            beam_wr <= 2'b00;
            beam_preupdate <= 1'b0;
        end else if (state == WRITE) begin
            beam_wr[0] <= `ADDR_MATCH(wb_adr_i, MASK_REG_0, 13'hF);
            beam_wr[1] <= `ADDR_MATCH(wb_adr_i, MASK_REG_1, 13'hF);
            // matches EITHER
            beam_preupdate <= wb_dat_i[31] && `ADDR_MATCH(wb_adr_i[13:0], MASK_REG_0, 13'h8);
        end
        if (state == WRITE && `ADDR_MATCH(wb_adr_i, MASK_REG_0, 13'hF))
            beam_mask[0 +: 18] <= wb_dat_i[0 +: 18];
        if (state == WRITE && `ADDR_MATCH(wb_adr_i, MASK_REG_1, 13'hF))
            beam_mask[18 +: 30] <= wb_dat_i[0 +: 30];                        
    end

    assign beam_write_wbclk = (state == ISSUE_WRITE);
    flag_sync u_write_sync(.in_clkA(beam_write_wbclk),.out_clkB(beam_write_ifclk),
                           .busy_clkA(beam_write_busy_wbclk),
                           .clkA(wb_clk_i),.clkB(ifclk));
                                   
    always @(posedge ifclk) begin
        beam_wr_ifclk[0] <= beam_write_ifclk && beam_wr[0];
        beam_wr_ifclk[1] <= beam_write_ifclk && beam_wr[1];
        beam_preupdate_ifclk <= beam_write_ifclk && beam_preupdate;
        beam_update <= beam_preupdate_ifclk;
    end
    
    assign beam_mask_o = beam_mask;
    assign beam_mask_wr_o = beam_wr_ifclk;
    assign beam_mask_update_o = beam_update;
    
    assign gen_rst_o = gen_rst;
    
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = wb_dat;    
endmodule
