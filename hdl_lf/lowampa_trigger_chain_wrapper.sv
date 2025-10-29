`timescale 1ns / 1ps
`include "interfaces.vh"

`define STARTSCALE 18'd1800
`define STARTOFFSET 16'd0

// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module lowampa_trigger_chain_wrapper #( parameter AGC_TIMESCALE_REDUCTION_BITS = 4,
                                parameter USE_BIQUADS = "FALSE",
                                parameter HDL_FILTER_VERSION = "DEFAULT",
                                parameter TARGET_RMS_SQUARED = 16,
                                parameter RMS_SQUARE_SCALE_ERR = 0,
                                parameter OFFSET_ERR = 5,
                                parameter STARTING_SCALE_DELTA = 30,
                                parameter STARTING_OFFSET_DELTA = 25,
                                parameter WBCLKTYPE = "PSCLK",
                                parameter CLKTYPE = "ACLK",
                                parameter AGC_CONTROL = "FALSE",
                                localparam NSAMP=4,
                                localparam NBITS=12,
                                localparam OUTBITS=5)(  


        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 8, 32 ), // Address width, data width. 

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_controller_ , 8, 32 ), // Address width, data width.
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input agc_reset_i,
        input aclk,
        input aclk_phase,
        input [NSAMP*NBITS-1:0] dat_i,
        output [1:0][47:0] dat_debug,
        output [NSAMP*OUTBITS-1:0] dat_o
    );

    // pack/unpack not needed here anymore    
    // WB interface to actual AGC module
    `DEFINE_WB_IF( wb_agc_module_ , 8, 32);

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [7:0] AGC_MASK = {8{1'b1}}; // May be unused
    // localparam NBITS_KP = 32;
    // localparam NFRAC_KP = 10;

    generate
        if (AGC_CONTROL == "TRUE") begin : AGCC
        
            // DOWNSTREAM CONTROL ///////////////////////////////////////////////////
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [21:0] address_agc = {8{1'b0}};
        
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [31:0] data_agc_o = {32{1'b0}};
            
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg use_agc_wb = 0; 
            
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg wr_agc_wb = 0; 
        
            assign wb_agc_module_dat_o = data_agc_o;
            assign wb_agc_module_adr_o = address_agc;
            assign wb_agc_module_cyc_o = use_agc_wb;
            assign wb_agc_module_stb_o = use_agc_wb;
            assign wb_agc_module_we_o = wr_agc_wb; // Tie this in too if only ever writing
            assign wb_agc_module_sel_o = {4{use_agc_wb}};
        
           
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [31:0] response_reg = 32'h0; // Pass back AGC information
        
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [5:0][31:0] agc_module_info_reg = {(6*32){1'b0}}; // Store of downstream AGC info
            wire[24:0] agc_sq_adjusted = {{(17-AGC_TIMESCALE_REDUCTION_BITS){1'd0}},{agc_module_info_reg[1][24:17-AGC_TIMESCALE_REDUCTION_BITS]}};
        
        
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [16:0] agc_control_scale_delta = STARTING_SCALE_DELTA; // change amount 
            
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [15:0] agc_control_offset_delta = STARTING_OFFSET_DELTA; // change amount 
        
            (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated agcs here
            reg [16:0] agc_recalculated_scale_reg = `STARTSCALE;
            
            (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated agcs here
            reg [15:0] agc_recalculated_offset_reg = `STARTOFFSET;
        
        
            // (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the agcs here
            // reg [NBEAMS-1:0][17:0] agc_regs = {NBEAMS{`STARTTHRESH}};
        
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            reg [31:0] agc_module_response = 32'h0; 
        
            // Upstream State machine control
            localparam FSM_BITS = 2;
            localparam [FSM_BITS-1:0] IDLE = 0;
            localparam [FSM_BITS-1:0] WRITE = 1;
            localparam [FSM_BITS-1:0] READ = 2;
            localparam [FSM_BITS-1:0] ACK = 3;
            reg [FSM_BITS-1:0] state = IDLE;   
        
            task do_write_to_agc; 
                input [21:0] in_addr;
                input [31:0] in_data;
                begin
                    address_agc = in_addr;
                    data_agc_o = `DLYFF in_data;
                    use_agc_wb = 1'b1;
                    wr_agc_wb = 1'b1;
                end
            endtask
        
            task finish_write_cycle_agc; 
                begin
                    use_agc_wb = 1'b0;
                    wr_agc_wb = 1'b0;
                    address_agc = 22'h0;
                    data_agc_o = 32'h0;
                end
            endtask
        
            task do_read_req_agc; 
                input [21:0] in_addr;
                begin
                    address_agc = in_addr;
                    use_agc_wb = 1'b1;
                    wr_agc_wb = 1'b0;
                end
            endtask
        
            task finish_read_cycle_agc; 
                output [31:0] out_data;
                begin
                    out_data = wb_agc_module_dat_i;
                    use_agc_wb = 1'b0;
                    wr_agc_wb = 1'b0;
                    address_agc = 22'h0;
                end
            endtask
        
            //////////////////////////////////////////////////////////
            //////        Wishbone FSM For Upstream Comms       //////
            //////////////////////////////////////////////////////////
            always @(posedge wb_clk_i) begin
                if (wb_rst_i) begin
                    state <= IDLE;
                    response_reg <= 32'h0;
                    agc_control_scale_delta <= STARTING_SCALE_DELTA;
                    agc_control_offset_delta <= STARTING_OFFSET_DELTA;
        //            agc_module_info_reg <= {(6*32){1'b0}};
                    // Add any other registers you want to reset here
                end else begin
                    // Determine what we are doing this cycle
                    case (state)
                        IDLE: if (wb_agc_controller_cyc_i && wb_agc_controller_stb_i) begin
                            if (wb_agc_controller_we_i) state <= WRITE;
                            else state <= READ;
                        end
                        WRITE: state <= ACK;
                        READ: state <= ACK;
                        ACK: state <= IDLE;
                        default: state <= IDLE; // Should never go here
                    endcase
                    
                    // If reading, load the response in
                    if (state == READ) begin
                        // If bit [6] is 1, return from control loop info
                        // Else, bit [6] is 0, return from AGC module info
                        if(wb_agc_controller_adr_i[6]) begin 
                            case (wb_agc_controller_adr_i[5:2])
                                0: response_reg <= {{(32-17){1'b0}}, agc_control_scale_delta};
                                1: response_reg <= {{(32-16){agc_control_offset_delta[15]}}, agc_control_offset_delta};
                            endcase
                            // response_reg <= agc_info_reg[wb_agc_controller_adr_i[3:0]];
                        end else begin
                            response_reg <= agc_module_info_reg[wb_agc_controller_adr_i[5:2]];
                        end
                    end
                    // If writing to a threshold, put it in the appropriate register
                    if (state == WRITE) begin
                        // NO CURRENT NEED FOR WRITING, CAN IMPLEMENT LATER           
                    end
                end
            end
        
        
        
            // Downstream State machine control
            localparam AGC_MODULE_FSM_BITS = 4;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_RESETTING = 0;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_POLLING = 1;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_WAITING = 2;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_READING = 3;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_CALCULATING = 4;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_WRITING = 5;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_LOADING = 6;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_APPLYING = 7;
            localparam [AGC_MODULE_FSM_BITS-1:0] AGC_MODULE_BOOT_DELAY = 8;
        
            localparam COMM_FSM_BITS = 2;
            localparam [COMM_FSM_BITS-1:0] COMM_SENDING = 0;
            localparam [COMM_FSM_BITS-1:0] COMM_WAITING = 1;
            localparam [COMM_FSM_BITS-1:0] COMM_PROCESSING = 2;
            // localparam [COMM_FSM_BITS-1:0] AGC_MODULE_READING = 2;
            // localparam [COMM_FSM_BITS-1:0] AGC_MODULE_CALCULATING = 3;
            // localparam [COMM_FSM_BITS-1:0] AGC_MODULE_WRITING = 4;
        
            reg [AGC_MODULE_FSM_BITS-1:0] agc_module_FSM_state = AGC_MODULE_BOOT_DELAY;  
            reg [AGC_MODULE_FSM_BITS-1:0] comm_FSM_state = COMM_SENDING;  
            reg [2:0] agc_module_info_idx = 0; // Control what agc data we are looking at
            reg [4:0] boot_delay_count = 5'b11111;
            
            
            /////////////////////////////////////////////////////////////////
            //////       Control Loop FSM For Downstream Control       //////
            /////////////////////////////////////////////////////////////////
            always @(posedge wb_clk_i) begin
                if (wb_rst_i || agc_reset_i) begin
                    agc_module_FSM_state <= AGC_MODULE_BOOT_DELAY;
                    comm_FSM_state <= COMM_SENDING;
                    agc_module_info_idx <= 0;
                    boot_delay_count <= 5'b11111;
                    agc_recalculated_scale_reg <= `STARTSCALE;
                    agc_recalculated_offset_reg <= `STARTOFFSET;
                    agc_module_response <= 32'h0;
                    // Add any other registers you want to reset here
                end else begin
                    // Determine what we are doing this cycle
                    case (agc_module_FSM_state)
                        AGC_MODULE_RESETTING: begin // Reset AGC Cycle 0
                            if(comm_FSM_state == COMM_SENDING) begin
                                do_write_to_agc(22'h0, 32'h04); // Reset signal
                                comm_FSM_state <= COMM_WAITING;
                            end else if(comm_FSM_state == COMM_WAITING) begin
                                if(wb_agc_module_ack_i) begin // Command received, move on
                                    finish_write_cycle_agc();
                                    agc_module_FSM_state <= AGC_MODULE_POLLING;
                                    comm_FSM_state <= COMM_SENDING;
                                end
                            end
                        end
                        AGC_MODULE_POLLING: begin // Start an agc sample cycle 1
                            if(comm_FSM_state == COMM_SENDING) begin
                                do_write_to_agc(22'h0, 32'h01);
                                comm_FSM_state <= COMM_WAITING;
                            end else if(comm_FSM_state == COMM_WAITING) begin
                                if(wb_agc_module_ack_i) begin // Command received, move on
                                    finish_write_cycle_agc();
                                    agc_module_FSM_state <= AGC_MODULE_WAITING;
                                    comm_FSM_state <= COMM_SENDING;
                                end
                            end
                        end
                        AGC_MODULE_WAITING: begin // Wait for agc cycle to finish 2
                            if(comm_FSM_state == COMM_SENDING) begin
                                do_read_req_agc(22'h0);
                                comm_FSM_state <= COMM_WAITING;
                            end else if(comm_FSM_state == COMM_WAITING) begin
                                if(wb_agc_module_ack_i) begin // Command received, move on
                                    finish_read_cycle_agc(agc_module_response);
                                    comm_FSM_state <= COMM_PROCESSING;
                                end
                            end else if(comm_FSM_state == COMM_PROCESSING) begin
                                if(agc_module_response[1] == 1) begin // If the agc cycle is done, move on (yes bit [1] is correct)
                                    agc_module_FSM_state <= AGC_MODULE_READING;
                                    agc_module_info_idx <= 0;
                                    comm_FSM_state <= COMM_SENDING;
                                end else begin // If the count cycle isn't done, ask again next clock
                                    comm_FSM_state <= COMM_SENDING;
                                end
                            end
                        end
                        AGC_MODULE_READING: begin // Read the agc status information 3
                            if(agc_module_info_idx < 6) begin
                                if(comm_FSM_state == COMM_SENDING) begin
                                    do_read_req_agc({17'h0, agc_module_info_idx, 2'b00}); // Request a read of agc info
                                    comm_FSM_state <= COMM_WAITING;
                                end else if(comm_FSM_state == COMM_WAITING) begin
                                    if(wb_agc_module_ack_i) begin // Command received, move on
                                        finish_read_cycle_agc(agc_module_response);
                                        comm_FSM_state <= COMM_PROCESSING;
                                    end
                                end else if(comm_FSM_state == COMM_PROCESSING) begin
                                    agc_module_info_reg[agc_module_info_idx] <= agc_module_response; // Record the count
                                    agc_module_info_idx <= agc_module_info_idx + 1; // Go to next beam
                                    comm_FSM_state <= COMM_SENDING; // Restart read cycle
                                end
                            end else begin // Move on, and reset beam counter
                                agc_module_FSM_state <= AGC_MODULE_CALCULATING;
                                agc_module_info_idx <= 0;
                            end
                        end
                        AGC_MODULE_CALCULATING: begin // Calculate the acale and threshold updates from recent count 4
        
                            // Will figure out multiplication in the future
                            // For now just simply raise or lower by set amount
        
        
        
                            // SCALE
                            if(agc_sq_adjusted > (TARGET_RMS_SQUARED + RMS_SQUARE_SCALE_ERR)) begin
                                if(agc_module_info_reg[4] > 17'h0012C) begin // Cutoff
                                    agc_recalculated_scale_reg = agc_module_info_reg[4] - agc_control_scale_delta;
                                end else begin
                                    agc_recalculated_scale_reg = agc_module_info_reg[4];
                                end
                            end else if(agc_sq_adjusted < (TARGET_RMS_SQUARED - RMS_SQUARE_SCALE_ERR)) begin
                                if(agc_module_info_reg[4] < 17'h1FBD0) begin // Cutoff
                                    agc_recalculated_scale_reg = agc_module_info_reg[4] + agc_control_scale_delta;
                                end else begin
                                    agc_recalculated_scale_reg = agc_module_info_reg[4];
                                end
                            end
        
                            // OFFSET GT-LT
                            if(agc_module_info_reg[2] > (agc_module_info_reg[3] + OFFSET_ERR)) begin
                                agc_recalculated_offset_reg = agc_module_info_reg[5] - agc_control_offset_delta;
                            end else if(agc_module_info_reg[3] > (agc_module_info_reg[2] + OFFSET_ERR)) begin
                                agc_recalculated_offset_reg = agc_module_info_reg[5] + agc_control_offset_delta;
                            end
                            agc_module_FSM_state <= AGC_MODULE_WRITING;
        
                        end
                        AGC_MODULE_WRITING: begin // Write the updated AGC values
                            if(agc_module_info_idx == 0) begin   // SCALE
                                if(comm_FSM_state == COMM_SENDING) begin 
                                    do_write_to_agc(17'h10, {{(32-17){1'b0}}, agc_recalculated_scale_reg}); // Request a read of the trigger count
                                    comm_FSM_state <= COMM_WAITING;
                                end else if(comm_FSM_state == COMM_WAITING) begin
                                    if(wb_agc_module_ack_i) begin // Command received, move on
                                        finish_write_cycle_agc();
                                        comm_FSM_state <= COMM_SENDING;
                                        agc_module_info_idx <= 1;
                                    end
                                end 
                            end else if(agc_module_info_idx == 1) begin // OFFSET
                                if(comm_FSM_state == COMM_SENDING) begin
                                    do_write_to_agc(17'h14, {{(32-16){agc_recalculated_offset_reg[15]}}, agc_recalculated_offset_reg}); // Request a read of the trigger count
                                    comm_FSM_state <= COMM_WAITING;
                                end else if(comm_FSM_state == COMM_WAITING) begin
                                    if(wb_agc_module_ack_i) begin // Command received, move on
                                        finish_write_cycle_agc();
                                        comm_FSM_state <= COMM_SENDING;
                                        agc_module_info_idx <= 2;
                                    end
                                end 
                            end else begin
                                agc_module_FSM_state <= AGC_MODULE_LOADING;
                                agc_module_info_idx <= 0;
                            end
                        end
                        AGC_MODULE_LOADING: begin // CE for each beam threshold 6
                            if(comm_FSM_state == COMM_SENDING) begin
                                do_write_to_agc(22'h0, 32'h300); // Load Scale and Offset
                                comm_FSM_state <= COMM_WAITING;
                            end else if(comm_FSM_state == COMM_WAITING) begin
                                if(wb_agc_module_ack_i) begin // Command received, move on
                                    finish_write_cycle_agc();
                                    comm_FSM_state <= COMM_SENDING;
                                    agc_module_FSM_state <= AGC_MODULE_APPLYING;
                                end
                            end 
                        end
                        AGC_MODULE_APPLYING: begin // 7
                            if(comm_FSM_state == COMM_SENDING) begin
                                do_write_to_agc(22'h0, 32'h400); // Apply Scale and Offset
                                comm_FSM_state <= COMM_WAITING;
                            end else if(comm_FSM_state == COMM_WAITING) begin
                                if(wb_agc_module_ack_i) begin // Command received, move on
                                    finish_write_cycle_agc();
                                    comm_FSM_state <= COMM_SENDING;
                                    agc_module_FSM_state <= AGC_MODULE_RESETTING;
                                    agc_module_info_reg[4] <= { {15{1'b0}},agc_recalculated_scale_reg};
                                    agc_module_info_reg[5] <= { {16{1'b0}},agc_recalculated_offset_reg};
                                end
                            end 
                        end
                        default:begin // Boot delay 8
                            if(boot_delay_count > 0) boot_delay_count <= boot_delay_count-1;
                            else agc_module_FSM_state <= AGC_MODULE_WRITING;
                        end
                    endcase
                end
            end

            // UPSTREAM RECEIVER ///////////////////////////////////////////////////
            // WB interface to the AGC control loop (in this module)
            // //  Top interface target (S)        Connection interface (M)
            assign wb_agc_controller_ack_o = (state == ACK);
            assign wb_agc_controller_err_o = 1'b0;
            assign wb_agc_controller_rty_o = 1'b0;
            assign wb_agc_controller_dat_o = response_reg;
        
        end else begin : NOCONTROL
            assign wb_agc_module_cyc_o = wb_agc_controller_cyc_i;
            assign wb_agc_module_stb_o = wb_agc_controller_stb_i;
            assign wb_agc_module_dat_o = wb_agc_controller_dat_i;
            assign wb_agc_module_adr_o = wb_agc_controller_adr_i;
            assign wb_agc_module_we_o = wb_agc_controller_we_i;
            assign wb_agc_module_sel_o = wb_agc_controller_sel_i;

            assign wb_agc_controller_ack_o = wb_agc_module_ack_i;
            assign wb_agc_controller_dat_o = wb_agc_module_dat_i;
            assign wb_agc_controller_rty_o = wb_agc_module_rty_i;
            assign wb_agc_controller_err_o = wb_agc_module_err_i;            
        end
    endgenerate    
    
    // clarify the connections rather than just staging for easier inspection
    // in the implemented design/elaborated design
    wire [NBITS*NSAMP-1:0] lpf_out;
    reg [NBITS*NSAMP-1:0] pipe_to_filter = {NBITS*NSAMP{1'b0}};
    wire [NBITS*NSAMP-1:0] match_out;
    reg [NBITS*NSAMP-1:0] pipe_to_biquad = {NBITS*NSAMP{1'b0}};
    wire [NBITS*NSAMP-1:0] biquad_out;
    
    wire [NBITS*NSAMP-1:0] to_agc;

    always @(posedge aclk) begin
        pipe_to_filter <= lpf_out;
        pipe_to_biquad <= match_out;        
    end 
    
    assign dat_debug[0] = pipe_to_filter;
    assign dat_debug[1] = pipe_to_biquad;

    // Low pass filter
    generate
        if (HDL_FILTER_VERSION == "HALF") begin : HB    
            shannon_whitaker_lpfull_vlowampa u_lpf (  .clk_i(aclk),
                                                .in_i(dat_i),
                                                .out_o(lpf_out));
        end else begin : TT       
            // comes out as a 13-bit object                                       
            wire [NSAMP-1:0][NBITS:0] lpf_out_tmp;
            twothirds_lpfull u_lpf (  .clk_i(aclk),
                .clk_phase_i(aclk_phase),
                .rst_i(reset_i),
                .dat_i(dat_i),
                .dat_o(lpf_out_tmp));
            genvar ii;
            for (ii=0;ii<NSAMP;ii=ii+1) begin : LP
                assign lpf_out[NBITS*ii +: NBITS] = lpf_out_tmp[ii][NBITS-1:0];
            end                           
        end
    endgenerate
    
    // Matched Filter
    lowampa_matched_filter_v3 u_matched_filter(
        .clk_i(aclk),
        .in_i(pipe_to_filter),
        .out_o(match_out)
    );

    // Biquads
    generate
        if (USE_BIQUADS == "TRUE") begin : BQ2
            reg [NBITS*NSAMP-1:0] pipe_to_agc = {NBITS*NSAMP{1'b0}};
            assign to_agc = pipe_to_agc;
            always @(posedge aclk) begin
                pipe_to_agc <= biquad_out;
            end
            biquad8_x2_wrapper #(.WBCLKTYPE(WBCLKTYPE),
                                 .CLKTYPE(CLKTYPE)) u_biquadx2(
                .wb_clk_i(wb_clk_i),
                .wb_rst_i(wb_rst_i),        
                `CONNECT_WBS_IFS( wb_ , wb_bq_ ),
                .reset_BQ_i(reset_i),
                .aclk(aclk),
                .dat_i(pipe_to_biquad),
                .dat_o(biquad_out)
            );
        end else begin : BYP
            wbs_dummy #(.ADDRESS_WIDTH(8),.DATA_WIDTH(32))
                u_bq(`CONNECT_WBS_IFS( wb_ , wb_bq_ ));
            // TODO replace this with the delay that you would normally
            // get from a biquad with unity gain
            assign biquad_out = pipe_to_biquad;
            assign to_agc = biquad_out;
        end
    endgenerate        

    agc_wrapper #(.TIMESCALE_REDUCTION((2**AGC_TIMESCALE_REDUCTION_BITS)),
                  .CLKTYPE(CLKTYPE),
                  .WBCLKTYPE(WBCLKTYPE),
                  .NSAMP(4))
     u_agc_wrapper(
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        `CONNECT_WBS_IFM( wb_ , wb_agc_module_ ),
        .aclk(aclk),
        .aresetn(reset_i),
        .dat_i(to_agc),
        .dat_o(dat_o)
    );


endmodule
