`timescale 1ns / 1ps
`include "interfaces.vh"
// the L1 trigger interconnect isn't combinatoric, it's registered
// because we want to cut down the cost and power to get to the stuff running in ACLK.
// we'll see.
module L1_trigger_intercon(
        input wb_clk_i,
        input clock_enabled_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ),
        `HOST_NAMED_PORTS_WB_IF( thresh_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( scaler_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( agc_ , 13, 32 ),
        `HOST_NAMED_PORTS_WB_IF( bq_ , 13, 32 ) 
    );

    localparam [1:0] MODULE_THRESH = 2'b00;
    localparam [1:0] MODULE_SCALER = 2'b01;
    localparam [1:0] MODULE_AGC = 2'b10;
    localparam [1:0] MODULE_BQ = 2'b11;
    
    reg [1:0]   module_select = {2{1'b0}};
        
    wire        thresh_select = (module_select == MODULE_THRESH) && clock_enabled_i;
    reg         thresh_cyc = 0;
    reg         thresh_we = 0;
    reg [12:0]  thresh_adr = {13{1'b0}};
    reg [31:0]  thresh_dat = {32{1'b0}};
    
    wire        scaler_select = (module_select == MODULE_SCALER) && clock_enabled_i;
    reg         scaler_cyc = 0;
    reg         scaler_we = 0;
    reg [12:0]  scaler_adr = {13{1'b0}};
    reg [31:0]  scaler_dat = {32{1'b0}};
    
    
    wire        agc_select = (module_select == MODULE_AGC) && clock_enabled_i;
    reg         agc_cyc = 0;
    reg         agc_we = 0;
    reg [12:0]  agc_adr = {13{1'b0}};
    reg [31:0]  agc_dat = {32{1'b0}};

    wire        bq_select = (module_select == MODULE_BQ) && clock_enabled_i;
    reg         bq_cyc = 0;
    reg         bq_we = 0;
    reg [12:0]  bq_adr = {13{1'b0}};
    reg [31:0]  bq_dat = {32{1'b0}};
        
    reg [31:0]  mux_up_dat = {32{1'b0}};
    reg         mux_up_ack = 0;
    
    reg         no_ack = 0;
    
    reg         we = 0;
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] TRANSACTION = 1;
    localparam [FSM_BITS-1:0] ACK = 2;
    localparam [FSM_BITS-1:0] FINISH = 3;
    reg [FSM_BITS-1:0] state = IDLE;    
    
    always @(posedge wb_clk_i) begin
        // goes high in first entry into transaction
        // at that point the select is high, so downstream
        // data will capture only then.
        we <= (state == IDLE && wb_cyc_i && wb_we_i);
                    
        if (!thresh_select) thresh_dat <= {32{1'b0}};
        else if (we) thresh_dat <= wb_dat_i;
        else if (thresh_ack_i) thresh_dat <= thresh_dat_i;
        
        if (thresh_select && state == IDLE) thresh_adr <= wb_adr_i;
        if (thresh_select && state == IDLE) thresh_we <= wb_we_i;
        
        if (!scaler_select) scaler_dat <= {32{1'b0}};
        else if (we) scaler_dat <= wb_dat_i;
        else if (scaler_ack_i) scaler_dat <= scaler_dat_i;
        if (scaler_select && state == IDLE) scaler_adr <= wb_adr_i;
        if (scaler_select && state == IDLE) scaler_we <= wb_we_i;
                
        if (!agc_select) agc_dat <= {32{1'b0}};
        else if (we) agc_dat <= wb_dat_i;
        else if (agc_ack_i) agc_dat <= agc_dat_i;
        if (agc_select && state == IDLE) agc_adr <= wb_adr_i;
        if (agc_select && state == IDLE) agc_we <= wb_we_i;
        
        
        if (!bq_select) bq_dat <= {32{1'b0}};
        else if (we) bq_dat <= wb_dat_i;
        else if (bq_ack_i) bq_dat <= bq_dat_i;
        if (bq_select && state == IDLE) bq_adr <= wb_adr_i;
        if (bq_select && state == IDLE) bq_we <= wb_we_i;

        // wanna see something cool
        mux_up_dat <= thresh_dat | scaler_dat | agc_dat | bq_dat;
        mux_up_ack <= thresh_ack_i | scaler_ack_i | agc_ack_i | bq_ack_i | no_ack;

        if (wb_cyc_i && state == IDLE)
            module_select <= wb_adr_i[14:13];
        
        case (state)
            IDLE: if (wb_cyc_i) state <= TRANSACTION;
            TRANSACTION: state <= ACK;
            ACK: if (mux_up_ack) state <= FINISH;
            FINISH: state <= IDLE;
        endcase            

        no_ack <= (state == IDLE && !clock_enabled_i);        

        if (thresh_ack_i) thresh_cyc <= 0;
        else if (state == TRANSACTION && thresh_select) thresh_cyc <= 1;
        
        if (scaler_ack_i) scaler_cyc <= 0;
        else if (state == TRANSACTION && scaler_select) scaler_cyc <= 1;
        
        if (agc_ack_i) agc_cyc <= 0;
        else if (state == TRANSACTION && agc_select) agc_cyc <= 1;

        if (bq_ack_i) bq_cyc <= 0;        
        else if (state == TRANSACTION && bq_select) bq_cyc <= 1;
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
        
    assign scaler_cyc_o = scaler_cyc;
    assign scaler_stb_o = scaler_cyc;
    assign scaler_adr_o = scaler_adr;
    assign scaler_dat_o = scaler_dat;
    assign scaler_we_o = scaler_we;
    assign scaler_sel_o = 4'hF;
    
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
