`timescale 1ns / 1ps

`define DLYFF #0.1
module beamscaler_tb;
    wire ifclk;
    wire wbclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(8.0)) u_ifclk(.clk(ifclk));

    // try with 6 beams, so need 12 threshold outputs
    reg [11:0] count_in = {12{1'b0}};

    reg rst = 1;
    reg [6:0] scal_addr = {7{1'b0}};
    wire [7:0] scal_addr_in = {1'b0, scal_addr};
    reg scal_rd = 0;
    wire [31:0] scal_dat;
    
    localparam [14:0] SIM_TIMER = 5000;
    wire timer_done;
    reg timer = 0;
    reg signed [15:0] timer_count = SIM_TIMER - 1;
    always @(posedge wbclk) begin
        timer <= timer_count < 0;
        if (timer_count < 0) timer_count <= SIM_TIMER - 1;
        else timer_count <= timer_count - 1;
    end
    // just dumb testing at the moment    
    beamscaler_wrap #(.NBEAMS(6))
            uut(.ifclk_i(ifclk),
                .count_i(count_in),
                .timer_i(timer),
                .done_o(timer_done),
                .wb_clk_i(wbclk),
                .wb_rst_i(rst),
                .scal_adr_i(scal_addr_in),
                .scal_rd_i(scal_rd),
                .scal_dat_o(scal_dat));

    reg capture_me = 0;
    reg [31:0] capture_dat = {32{1'b0}};
    always @(posedge wbclk) begin
        if (capture_me) capture_dat <= scal_dat;
    end

    integer i;
    initial begin
        #100;
        @(posedge wbclk);
        #0.1 rst = 0;
        @(posedge wbclk);
        #100;
        @(posedge ifclk);
        #0.1 count_in[0] = 1;
             count_in[5] = 1;
        @(posedge ifclk);
        #0.1 count_in[0] = 0;   // beam 0 scaler 0 = 1
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
        @(posedge ifclk);             
//        #0.1 count_in[5] = 0;   // beam 2 scaler 1 = 9
        #40;
        @(posedge ifclk);
        #0.1 count_in[3] = 1;
        @(posedge ifclk);
        @(posedge ifclk);
        @(posedge ifclk);
        #0.1 count_in[3] = 0;   // beam 1 scaler 1 = 3
        @(posedge ifclk);
        #0.1 count_in[8] = 1;
        @(posedge ifclk);
        @(posedge ifclk);
        @(posedge ifclk);
        @(posedge ifclk);
        @(posedge ifclk);
        @(posedge ifclk);
        #0.1 count_in[8] = 0;   // beam 4 scaler 0 = 6        
        
        while (!timer_done) @(posedge wbclk);
        
        #100;
        for (i=0;i<6;i=i+1) begin
            @(posedge wbclk); 
            #0.1 scal_rd = 1;
                 scal_addr = i;
            @(posedge wbclk);   // clock 0
            #0.1 scal_rd = 0;
            @(posedge wbclk);   // clock 1
            #0.1 capture_me = 1;
            @(posedge wbclk);
            #0.1 capture_me = 0;    
        end         
    end
endmodule
