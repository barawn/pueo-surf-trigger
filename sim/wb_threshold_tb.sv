`timescale 1ns / 1ps
`include "interfaces.vh"
module wb_threshold_tb;
    wire aclk;
    tb_rclk #(.PERIOD(2.667)) u_aclk(.clk(aclk));
    wire wb_clk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wb_clk));
    
    `DEFINE_WB_IF( wb_ , 12, 32 );
    reg cyc = 0;
    reg we = 0;
    reg [11:0] adr = {12{1'b0}};
    reg [31:0] dat = {32{1'b0}};
    assign wb_cyc_o = cyc;
    assign wb_stb_o = cyc;
    assign wb_we_o = we;
    assign wb_sel_o = 4'hF;
    assign wb_adr_o = adr;
    assign wb_dat_o = dat;
    
    reg scal_bank = 0;
    wire scal_timer;
    wire scal_rst;
    
    wire [1:0][17:0] thresh;
    wire [1:0] thresh_wr;
    wire [1:0] thresh_update;
    wb_thresholds #(.DEFAULT_COUNT(100))
                  uut(.wb_clk_i(wb_clk),
                      `CONNECT_WBS_IFM( wb_ , wb_ ),
                      .scal_bank_i(scal_bank),
                      .scal_timer_o(scal_timer),
                      .scal_rst_o(scal_rst),
                      .aclk(aclk),
                      .thresh_o(thresh),
                      .thresh_wr_o(thresh_wr),
                      .thresh_update_o(thresh_update));

    task wb_write;
        input [15:0] addr;
        input [31:0] data;
        begin
            @(posedge wb_clk);
            #0.1 cyc = 1;
                 we = 1;
                 adr = {addr[12],addr[10:0]};
                 dat = data;
            while (!wb_ack_i) @(posedge wb_clk);
            #0.1 cyc = 0;
                 we = 0;
                 adr = {12{1'b0}};
                 dat = {32{1'b0}};
            @(posedge wb_clk);                
        end
    endtask
    
    reg [31:0] wb_rd_data = {32{1'b0}};
    always @(posedge wb_clk) begin
        if (wb_cyc_o && wb_stb_o && wb_ack_i)
            wb_rd_data <= wb_dat_i;
    end
    
    task wb_read;
        input [15:0] addr;
        begin
            @(posedge wb_clk);
            #0.1 cyc = 1;
                 adr = {addr[12],addr[10:0]};
            while (!wb_ack_i) @(posedge wb_clk);
            #0.1 cyc = 0;
                 adr = {12{1'b0}};
                 $display("time %0t read 0x%0h", $time, wb_rd_data);
            @(posedge wb_clk);                                  
        end
    endtask
    
    initial begin
        #200;
        wb_write(16'h0800, 32'd5000);
        wb_write(16'h0804, 32'd4000);
        wb_write(16'h0808, 32'd3000);
        wb_write(16'h080C, 32'd2000);

        wb_write(16'h0A00, 32'd5001);
        wb_write(16'h0A04, 32'd100);
        wb_write(16'h0A08, 32'd50);
        wb_write(16'h0A0C, 32'd25);
        
        wb_read(16'h0800);
        wb_read(16'h0804);
        wb_read(16'h0808);
        
        wb_write(16'h1800, 32'h2);
        wb_write(16'h1808, 32'h200);
        #1000;
        wb_read(16'h1808);
    end
    
endmodule
