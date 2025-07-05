`timescale 1ns / 1ps
`include "interfaces.vh"
// the L1 trigger interconnect isn't combinatoric, it's registered
// because we want to cut down the cost and power to get to the stuff running in ACLK.
module L1_trigger_intercon(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ),
        `HOST_NAMED_PORTS_WB_IF( thresh_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( generator_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( agc_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( bq_ , 13, 32 ) 
    );

    localparam [1:0] MODULE_THRESH = 2'b00;
    localparam [1:0] MODULE_GENERATOR = 2'b01;
    localparam [1:0] MODULE_AGC = 2'b10;
    localparam [1:0] MODULE_BQ = 2'b11;
    
    wire [1:0]  module_select = (wb_adr_i[14:13]);
        
    wire        thresh_select = (module_select == MODULE_THRESH);
    reg         thresh_cyc = 0;
    reg         thresh_we = 0;
    reg [12:0]  thresh_adr = {13{1'b0}};
    reg [31:0]  thresh_dat = {32{1'b0}};
    
    wire        generator_select = (module_select == MODULE_GENERATOR);
    reg         generator_cyc = 0;
    reg         generator_we = 0;
    reg [12:0]  generator_adr = {13{1'b0}};
    reg [31:0]  generator_dat = {32{1'b0}};
    
    
    wire        agc_select = (module_select == MODULE_AGC);
    reg         agc_cyc = 0;
    reg         agc_we = 0;
    reg [12:0]  agc_adr = {13{1'b0}};
    reg [31:0]  agc_dat = {32{1'b0}};

    wire        bq_select = (module_select == MODULE_BQ);
    reg         bq_cyc = 0;
    reg         bq_we = 0;
    reg [12:0]  bq_adr = {13{1'b0}};
    reg [31:0]  bq_dat = {32{1'b0}};
        
    reg [31:0]  mux_up_dat = {32{1'b0}};
    reg         mux_up_ack = 0;
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] TRANSACTION = 1;
    localparam [FSM_BITS-1:0] FINISH = 2;
    reg [FSM_BITS-1:0] state = IDLE;    
    
    always @(posedge wb_clk_i) begin
        if (!thresh_select) thresh_dat <= {32{1'b0}};
        else if (wb_we_i) thresh_dat <= wb_dat_i;
        else if (thresh_ack_i) thresh_dat <= thresh_dat_i;
        if (thresh_select && state == IDLE) thresh_adr <= wb_adr_i;
        if (thresh_select && state == IDLE) thresh_we <= wb_we_i;
        
        if (!generator_select) generator_dat <= {32{1'b0}};
        else if (wb_we_i) generator_dat <= wb_dat_i;
        else if (generator_ack_i) generator_dat <= generator_dat_i;
        if (generator_select && state == IDLE) generator_adr <= wb_adr_i;
        if (generator_select && state == IDLE) generator_we <= wb_we_i;
                
        if (!agc_select) agc_dat <= {32{1'b0}};
        else if (wb_we_i) agc_dat <= wb_dat_i;
        else if (agc_ack_i) agc_dat <= agc_dat_i;
        if (agc_select && state == IDLE) agc_adr <= wb_adr_i;
        if (agc_select && state == IDLE) agc_we <= wb_we_i;
        
        
        if (!bq_select) bq_dat <= {32{1'b0}};
        else if (wb_we_i) bq_dat <= wb_dat_i;
        else if (bq_ack_i) bq_dat <= bq_dat_i;
        if (bq_select && state == IDLE) bq_adr <= wb_adr_i;
        if (bq_select && state == IDLE) bq_we <= wb_we_i;

        // wanna see something cool
        mux_up_dat <= thresh_dat | generator_dat | agc_dat | bq_dat;
        mux_up_ack <= thresh_ack_i | generator_ack_i | agc_ack_i | bq_ack_i;
        
        case (state)
            IDLE: if (wb_cyc_i) state <= TRANSACTION;
            TRANSACTION: if (mux_up_ack) state <= FINISH;
            FINISH: state <= IDLE;
        endcase            

        if (state == IDLE && thresh_select) thresh_cyc <= 1;
        else if (thresh_ack_i) thresh_cyc <= 0;
        
        if (state == IDLE && generator_select) generator_cyc <= 1;
        else if (generator_ack_i) generator_cyc <= 0;
        
        if (state == IDLE && agc_select) agc_cyc <= 1;
        else if (agc_ack_i) agc_cyc <= 0;
        
        if (state == IDLE && bq_select) bq_cyc <= 1;
        else if (bq_ack_i) bq_cyc <= 0;
    end

    assign wb_ack_o = (state == FINISH);
    assign wb_dat_o = mux_up_dat;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    
    assign thresh_cyc_o = thresh_cyc;
    assign thresh_stb_o = thresh_cyc;
    assign thresh_adr_o = thresh_adr;
    assign thresh_dat_o = thresh_dat;
    assign thresh_we_o =  thresh_we;
    assign thresh_sel_o = 4'hF;
        
    assign generator_cyc_o = generator_cyc;
    assign generator_stb_o = generator_cyc;
    assign generator_adr_o = generator_adr;
    assign generator_dat_o = generator_dat;
    assign generator_we_o = generator_we;
    assign generator_sel_o = 4'hF;
    
    assign agc_cyc_o = agc_cyc;
    assign agc_stb_o = agc_cyc;
    assign agc_adr_o = agc_adr;
    assign agc_dat_o = agc_dat;
    assign agc_we_o =  agc_we;
    assign agc_sel_o = 4'hF;

    assign bq_cyc_o = bq_cyc;
    assign bq_stb_o = bq_cyc;
    assign bq_adr_o = bq_adr;
    assign bq_dat_o = bq_dat;
    assign bq_we_o =  bq_we;
    assign bq_sel_o = 4'hF;
            
endmodule
