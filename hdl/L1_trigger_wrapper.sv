`timescale 1ns / 1ps
`include "interfaces.vh"

`define USING_DEBUG 1
`define DLYFF #0.1
`define STARTTHRESH 18'd3500

module L1_trigger_wrapper #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK",
                    parameter [47:0] TRIGGER_CLOCKS=375000000*10,// at 375 MHz this will count for 10 seconds  
                    parameter HOLDOFF_CLOCKS=16,        // NOTE: Parameters are 32 bit max, which this exceeds
                    parameter STARTING_TARGET=100, // At 100 s period, this will be 1 Hz
                    parameter STARTING_KP=2,
                    parameter COUNT_MARGIN=10)( 

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        `ifdef USING_DEBUG
        output [7:0][39:0] dat_o,
        output [7:0][1:0][95:0] dat_debug,
        `endif
        output [NBEAMS-1:0] trigger_o
    );

    task do_write_to_trigger; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            address_threshold = in_addr;
            data_threshold_o = `DLYFF in_data;
            use_threshold_wb = 1'b1;
            wr_threshold_wb = 1'b1;
        end
    endtask

    task finish_write_cycle_trigger; 
        begin
            use_threshold_wb = 1'b0;
            wr_threshold_wb = 1'b0;
            address_threshold = 22'h0;
            data_threshold_o = 32'h0;
        end
    endtask

    task do_read_req_trigger; 
        input [21:0] in_addr;
        begin
            address_threshold = in_addr;
            use_threshold_wb = 1'b1;
            wr_threshold_wb = 1'b0;
        end
    endtask

    task finish_read_cycle_trigger; 
        output [31:0] out_data;
        begin
            out_data = wb_threshold_dat_i;
            use_threshold_wb = 1'b0;
            wr_threshold_wb = 1'b0;
            address_threshold = 22'h0;
        end
    endtask

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};
    localparam NBITS_KP = 32;
    localparam NFRAC_KP = 10;

    // Pass commands not about trigger rate control loop down
    `DEFINE_WB_IF( wb_L1_submodule_ , 22, 32);
    
    `DEFINE_WB_IF( wb_threshold_ , 22, 32);
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [21:0] address_threshold = {22{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] data_threshold_o = {32{1'b0}};
    //reg [31:0] data_threshold_i;
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg use_threshold_wb = 0; // QOL tie these together if not ever implementing writing
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg wr_threshold_wb = 0; // QOL tie these together if not ever implementing writing

    assign wb_threshold_dat_o = data_threshold_o;
    // assign data_threshold_i = wb_threshold_dat_i;
    assign wb_threshold_adr_o = address_threshold;
    assign wb_threshold_cyc_o = use_threshold_wb;
    assign wb_threshold_stb_o = use_threshold_wb;
    assign wb_threshold_we_o = wr_threshold_wb; // Tie this in too if only ever writing
    assign wb_threshold_sel_o = {4{use_threshold_wb}};

    // //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[14]) ? wb_L1_submodule_ack_i : (state == ACK);
    assign wb_err_o = (wb_adr_i[14]) ? wb_L1_submodule_err_i : 1'b0;
    assign wb_rty_o = (wb_adr_i[14]) ? wb_L1_submodule_rty_i : 1'b0;
    assign wb_dat_o = (wb_adr_i[14]) ? wb_L1_submodule_dat_i : response_reg;
    
    wire wb_control_loop_cyc_i;

    assign wb_L1_submodule_cyc_o = wb_cyc_i && wb_adr_i[14];
    assign wb_control_loop_cyc_i = wb_cyc_i && !wb_adr_i[14];
    assign wb_L1_submodule_stb_o = wb_stb_i;
    assign wb_L1_submodule_adr_o = wb_adr_i;
    assign wb_L1_submodule_dat_o = wb_dat_i;
    assign wb_L1_submodule_we_o = wb_we_i;
    assign wb_L1_submodule_sel_o = wb_sel_i;  

   
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 32'h0; // Pass back trigger count information

    // (* CUSTOM_CC_DST = WBCLKTYPE *)
    // reg [31:0] trigger_count_wb_reg; // Pass back # of triggers on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_target_wb_reg = STARTING_TARGET; // The target number of triggers in the sample period

    // (* CUSTOM_CC_DST = WBCLKTYPE *)
    // reg [31:0] trigger_threshold_wb_reg; // Pass back threshold value on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBITS_KP-1:0] trigger_control_K_P = STARTING_KP; // P Parameter for control loop. 
                                            // This is the fraction of error value to change threshold by.
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the last measured counts (rates) here
    reg [NBEAMS-1:0][31:0] trigger_count_reg = {(NBEAMS*32){1'b0}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated thresholds here
    reg [NBEAMS-1:0][17:0] threshold_recalculated_regs = {NBEAMS{`STARTTHRESH}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the thresholds here
    reg [NBEAMS-1:0][17:0] threshold_regs = {NBEAMS{`STARTTHRESH}};

    // (* CUSTOM_CC_SRC = WBCLKTYPE *)
    // reg [17:0] threshold_writing = {18{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_response = 32'h0; // L1 trigger replies

    // Upstream State machine control
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;   

    //////////////////////////////////////////////////////////
    //////        Wishbone FSM For Upstream Comms       //////
    //////////////////////////////////////////////////////////
    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_control_loop_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            // If bit [10] is 1, return the last-measured trigger count
            // Else if bit [11] is 1, return the current trigger threshold
            // Else return the loop parameter
            if(wb_adr_i[10]) response_reg <= trigger_count_reg[wb_adr_i[9:2]];
            else if(wb_adr_i[11]) response_reg <= {{(32-18){1'b0}}, threshold_regs[wb_adr_i[9:2]]};
            else response_reg <= {{(32-NBITS_KP){1'b0}}, trigger_control_K_P};
        end
        if (state == WRITE) begin
            // NO CURRENT NEED FOR WRITING        
        end
    end



    // Downstream State machine control
    localparam THRESHOLD_FSM_BITS = 3;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_POLLING = 0;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_WAITING = 1;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_READING = 2;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_CALCULATING = 3;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_WRITING = 4;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_APPLYING = 5;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_UPDATING = 6;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_BOOT_DELAY = 7;

    localparam COMM_FSM_BITS = 2;
    localparam [COMM_FSM_BITS-1:0] COMM_SENDING = 0;
    localparam [COMM_FSM_BITS-1:0] COMM_WAITING = 1;
    localparam [COMM_FSM_BITS-1:0] COMM_PROCESSING = 2;
    // localparam [COMM_FSM_BITS-1:0] THRESHOLD_READING = 2;
    // localparam [COMM_FSM_BITS-1:0] THRESHOLD_CALCULATING = 3;
    // localparam [COMM_FSM_BITS-1:0] THRESHOLD_WRITING = 4;

    reg [THRESHOLD_FSM_BITS-1:0] threshold_FSM_state = THRESHOLD_BOOT_DELAY;  
    reg [THRESHOLD_FSM_BITS-1:0] comm_FSM_state = COMM_SENDING;  
    reg [$clog2(NBEAMS)+1:0] beam_idx = 0; // Control what beam we are looking at
    reg [4:0] boot_delay_count = 5'b11111;

    // wire [NBEAMS][31:0] threshold_recalculated_wire_out;
    
    /////////////////////////////////////////////////////////////////
    //////       Control Loop FSM For Downstream Control       //////
    /////////////////////////////////////////////////////////////////
    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (threshold_FSM_state)
            THRESHOLD_POLLING: begin // Start a trigger count cycle 0
                if(comm_FSM_state == COMM_SENDING) begin
                    do_write_to_trigger(22'h0, 32'h1);
                    comm_FSM_state <= COMM_WAITING;
                end else if(comm_FSM_state == COMM_WAITING) begin
                    if(wb_threshold_ack_i) begin // Command received, move on
                        finish_write_cycle_trigger();
                        threshold_FSM_state <= THRESHOLD_WAITING;
                        comm_FSM_state <= COMM_SENDING;
                    end
                end
            end
            THRESHOLD_WAITING: begin // Wait for count cycle to finish 1
                if(comm_FSM_state == COMM_SENDING) begin
                    do_read_req_trigger(22'h0);
                    comm_FSM_state <= COMM_WAITING;
                end else if(comm_FSM_state == COMM_WAITING) begin
                    if(wb_threshold_ack_i) begin // Command received, move on
                        finish_read_cycle_trigger(trigger_response);
                        comm_FSM_state <= COMM_PROCESSING;
                    end
                end else if(comm_FSM_state == COMM_PROCESSING) begin
                    if(trigger_response[0] == 1) begin // If the count cycle is done, move on
                        threshold_FSM_state <= THRESHOLD_READING;
                        beam_idx <= 0;
                        comm_FSM_state <= COMM_SENDING;
                    end else begin // If the count cycle isn't done, ask again next clock
                        comm_FSM_state <= COMM_SENDING;
                    end
                end
            end
            THRESHOLD_READING: begin // Loop over the beams, reading their most recent counts 2
                if(beam_idx < NBEAMS) begin
                    if(comm_FSM_state == COMM_SENDING) begin
                        do_read_req_trigger(22'h400 + beam_idx*4); // Request a read of the trigger count
                        comm_FSM_state <= COMM_WAITING;
                    end else if(comm_FSM_state == COMM_WAITING) begin
                        if(wb_threshold_ack_i) begin // Command received, move on
                            finish_read_cycle_trigger(trigger_response);
                            comm_FSM_state <= COMM_PROCESSING;
                        end
                    end else if(comm_FSM_state == COMM_PROCESSING) begin
                        trigger_count_reg[beam_idx] <= trigger_response; // Record the count
                        beam_idx <= beam_idx + 1; // Go to next beam
                        comm_FSM_state <= COMM_SENDING; // Restart read cycle
                    end
                end else begin // Move on, and reset beam counter
                    threshold_FSM_state <= THRESHOLD_CALCULATING;
                    beam_idx <= 0;
                end
            end
            THRESHOLD_CALCULATING: begin // Calculate the threshold updates from the recent trigger counts 3
                if(beam_idx < NBEAMS) begin
                    // Will figure out multiplication in the future
                    // For now just simply raise or lower by set amount
                    if(trigger_count_reg[beam_idx] > (trigger_target_wb_reg + COUNT_MARGIN)) begin
                        threshold_recalculated_regs[beam_idx] = threshold_regs[beam_idx] + trigger_control_K_P;
                    end else if (trigger_count_reg[beam_idx] < (trigger_target_wb_reg - COUNT_MARGIN)) begin
                        threshold_recalculated_regs[beam_idx] = threshold_regs[beam_idx] - trigger_control_K_P;
                    end
                    // TODO: Clip this
                    beam_idx <= beam_idx + 1;
                end else begin // Move on, and reset beam counter
                    threshold_FSM_state <= THRESHOLD_WRITING;
                    beam_idx <= 0;
                end
            end
            THRESHOLD_WRITING: begin // Write the updated thresholds to the L1 trigger 4
                if(beam_idx < NBEAMS) begin
                    if(comm_FSM_state == COMM_SENDING) begin
                        do_write_to_trigger(22'h400 + beam_idx*4, {{(32-18){1'b0}}, threshold_recalculated_regs[beam_idx]}); // Request a read of the trigger
                        
                        comm_FSM_state <= COMM_WAITING;
                    end else if(comm_FSM_state == COMM_WAITING) begin
                        if(wb_threshold_ack_i) begin // Command received, move on
                            finish_write_cycle_trigger();
                            comm_FSM_state <= COMM_SENDING;
                            beam_idx <= beam_idx + 1;
                        end
                    end 
                end else begin // Move on, reset beam counter
                    threshold_FSM_state <= THRESHOLD_APPLYING;
                    beam_idx <= 0;
                end
            end
            THRESHOLD_APPLYING: begin // CE for each beam threshold 5
                if(beam_idx < NBEAMS) begin
                    if(comm_FSM_state == COMM_SENDING) begin
                        do_write_to_trigger(22'h800 + beam_idx*4, 32'h1); // CE of this beam threshold
                        comm_FSM_state <= COMM_WAITING;
                    end else if(comm_FSM_state == COMM_WAITING) begin
                        if(wb_threshold_ack_i) begin // Command received, move on
                            finish_write_cycle_trigger();
                            comm_FSM_state <= COMM_SENDING;
                            beam_idx <= beam_idx + 1;
                        end
                    end 
                end else begin
                    threshold_FSM_state <= THRESHOLD_UPDATING;
                    beam_idx <= 0;
                end
            end
            THRESHOLD_UPDATING: begin // Update all thresholds 6
                if(comm_FSM_state == COMM_SENDING) begin
                    do_write_to_trigger(22'h0 , 32'h2); // Update all thresholds at once
                    comm_FSM_state <= COMM_WAITING;
                end else if(comm_FSM_state == COMM_WAITING) begin
                    if(wb_threshold_ack_i) begin // Command received, move on
                        finish_write_cycle_trigger();
                        comm_FSM_state <= COMM_SENDING;
                        threshold_regs <= threshold_recalculated_regs;
                        threshold_FSM_state <= THRESHOLD_POLLING;
                    end
                end 
            end
            default:begin // Boot delay 7
                if(boot_delay_count > 0) boot_delay_count <= boot_delay_count-1;
                else threshold_FSM_state <= THRESHOLD_WRITING; // Should never go here
            end
        endcase
    end



    L1_trigger #(   .AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS), 
                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS),
                    .NBEAMS(NBEAMS))
        u_L1_trigger(
            .wb_clk_i(wb_clk_i),
            .wb_rst_i(wb_rst_i),
            `CONNECT_WBS_IFM( wb_ , wb_L1_submodule_ ),
            `CONNECT_WBS_IFM( wb_threshold_ , wb_threshold_ ),
            .reset_i(reset_i), 
            .aclk(aclk),
            .dat_i(dat_i),
            
            `ifdef USING_DEBUG
            .dat_o(dat_o),
            .dat_debug(dat_debug),
            `endif
            
            .trigger_o(trigger_o));

endmodule
