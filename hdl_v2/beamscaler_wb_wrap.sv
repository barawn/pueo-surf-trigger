`timescale 1ns / 1ps
// This module does 2 things: first, wrap the WISHBONE access portion
// and two, generate the actual scalers.
//
// The output triggers arrive here in IFCLK, because the trig_cc_stretch
// exists in the L1_trigger_v2 now.
//
// This means that what we need to do is a rising edge detect plus stuck-on
// detection. Because our scalers are so small (1024 max, with a count-rate
// max of 125M) the stuck on detection doesn't need to be great, it just needs
// to prevent a rollover at stupid-high occupancy.
`include "interfaces.vh"
module beamscaler_wb_wrap #(parameter NBEAMS = 46,
                            parameter NSCALERS = 2,
                            parameter DEBUG = "FALSE",
                            parameter IFCLKTYPE = "NONE",
                            parameter WBCLKTYPE = "NONE")(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 12, 32 ),

        input ifclk_i,
        input [NBEAMS*NSCALERS-1:0] count_i,
        input timer_i,
        output done_o,
        output bank_o,
        input rst_i        
    );
    
    wire stuck_ce;
    clk_div_ce #(.CLK_DIVIDE(31))
        u_stuck_ce(.clk(ifclk_i),
                   .ce(stuck_ce));
    
    wire [NBEAMS*NSCALERS-1:0] scaler_in;
    generate
        genvar i;
        for (i=0;i<NBEAMS*NSCALERS;i=i+1) begin : SCCONV
            // we saturate at a stupid low occupancy level so this will turn on
            // when a signal's been on for 96 clocks = nearly 1 microsecond
            reg count_rereg = 0;
            reg [2:0] stuck_shreg = {3{1'b0}};
            reg scaler = 0;
            always @(posedge ifclk_i) begin : LG
                count_rereg <= count_i[i];
                if (!count_i) stuck_shreg <= 3'b000;
                else if (stuck_ce) stuck_shreg <= {stuck_shreg[1:0], count_i[i]};
                
                scaler <= (count_i[i] && !count_rereg) || stuck_shreg[2];
            end
            assign scaler_in[i] = scaler;
        end
    endgenerate    

    // our WB interface can be stupidly simple since we always do the same thing
    localparam [1:0] FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] READ = 1;
    localparam [FSM_BITS-1:0] WAIT_0 = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    always @(posedge wb_clk_i) begin
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                     if (!wb_we_i) state <= READ;
                     else state <= ACK;
                  end
            READ: state <= WAIT_0;
            WAIT_0: state <= ACK;
            ACK: state <= IDLE;
        endcase
    end

    // address is just the bottom 8 bits now
    beamscaler_wrap #(.NBEAMS(NBEAMS),
                      .IFCLKTYPE(IFCLKTYPE),
                      .WBCLKTYPE(WBCLKTYPE),
                      .DEBUG(DEBUG))
        u_bs( .ifclk_i(ifclk_i),
              .count_i(scaler_in),
              .timer_i(timer_i),
              .done_o(done_o),
              .write_bank_o(bank_o),
              .wb_clk_i(wb_clk_i),
              .wb_rst_i(rst_i),
              .scal_rd_i(state == READ),
              .scal_adr_i(wb_adr_i[2 +: 8]),
              .scal_dat_o(wb_dat_o));
    
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    
endmodule
