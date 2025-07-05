`timescale 1ns / 1ps
`include "interfaces.vh"

`ifndef DLYFF
`define DLYFF #0.1
`endif

module L1_trigger_loop_tb;

    `DEFINE_WB_IF( wb_ , 22, 32 );

    wire wb_clk;
    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(wb_clk));
    
    reg [31:0] dat = {32{1'b0}};
    reg ack = 0;
    always @(posedge wb_clk) begin
        ack <= `DLYFF (wb_cyc_o && wb_stb_o);
    end    
    assign wb_ack_i = ack && wb_cyc_o;
    assign wb_dat_i = dat;
    assign wb_err_i = 1'b0;
    assign wb_rty_i = 1'b0;
        
    reg loop_enable = 0;
    wire reset_complete;

    reg [31:0] target_rate = {32{1'b0}};
    reg [15:0] target_delta = {16{1'b0}};
    
    reg [31:0] thresh_dat = {32{1'b0}};
    reg [5:0] thresh_idx = {6{1'b0}};
    reg thresh_upd = 0;
    reg thresh_wr = 0;
    wire thresh_ack;
    wire [17:0] thresh_dat_out;
    
    reg [5:0] scal_idx = {6{1'b0}};
    wire [31:0] scal_dat_out;    
    
    reg [1:0] loop_state_req = {2{1'b0}};
    wire [1:0] loop_state;
    
    reg trig_count_done = 0;
    
    L1_trigger_loop uut(.wb_clk_i(wb_clk),
                        .loop_enable_i(loop_enable),
                        .reset_complete_o(reset_complete),
                        
                        .loop_state_req_i(loop_state_req),
                        .loop_state_o(loop_state),
                        
                        .target_rate_i(target_rate),
                        .target_delta_i(target_delta),
                        
                        .thresh_dat_i(thresh_dat),
                        .thresh_idx_i(thresh_idx),                        
                        .thresh_upd_i(thresh_upd),
                        .thresh_wr_i(thresh_wr),
                        .thresh_ack_o(thresh_ack),
                        .thresh_dat_o(thresh_dat_out),
                        
                        .scal_idx_i(scal_idx),
                        .scal_dat_o(scal_dat_out),
                        
                        `CONNECT_WBM_IFM(loop_ , wb_ ),
                        .trig_count_done_i(trig_count_done));

    task new_thresh;
        input [5:0] thr_idx;
        input [17:0] thr_val;
        begin
            @(posedge wb_clk);
            #1 thresh_idx = thr_idx;
               thresh_dat = thr_val;
               thresh_wr = 1;
            while (!thresh_ack) @(posedge wb_clk);
            #1 thresh_wr = 0;
            @(posedge wb_clk);
        end                
    endtask
    
    task thresh_update;
        begin
            @(posedge wb_clk);
            #1 thresh_upd = 1;
            while (!thresh_ack) @(posedge wb_clk);
            #1 thresh_upd = 0;
            @(posedge wb_clk);            
        end
    endtask
            
    initial begin
        #100;
        @(posedge wb_clk); #1 loop_enable <= `DLYFF 1;
        #4000;
        $display("Moving to stop state");
        @(posedge wb_clk); #1 loop_state_req = 2;
        while (loop_state != loop_state_req) @(posedge wb_clk);
        $display("In stop state, trying threshold write");
        new_thresh(15, 2000);
        $display("In stop state, trying update");
        thresh_update();
        $display("Update done?");
    end                        
                        
endmodule
