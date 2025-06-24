`timescale 1ns / 1ps
`include "interfaces.vh"
`include "L1Beams_header.vh"

`define USING_DEBUG 1
`define DLYFF #0.1
// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module L1_trigger #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK",
                    parameter [47:0] TRIGGER_CLOCKS=375000000,
                    parameter HOLDOFF_CLOCKS=16)( // at 375 MHz this will count for 1 s  

        input wb_clk_i,
        input wb_rst_i,

        // Two wishbone interfaces 

        // First controls AGC aqnd Biquads
        // Bit 12 differentiates between the two (0 for AGC, 1 for BQs)
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.

        // Second controls L1 thresholds
        `TARGET_NAMED_PORTS_WB_IF( wb_threshold_ , 22, 32 ), // Address width, data width.

        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,

        `ifdef USING_DEBUG
        output [7:0][39:0] dat_o,
        output [7:0][1:0][95:0] dat_debug,
        `endif

        output [NBEAMS-1:0] trigger_o
    );

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};

    // State machine control
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] DELAY = 3;
    localparam [FSM_BITS-1:0] ACK = 4;
    reg [FSM_BITS-1:0] state = IDLE;    

    localparam HOLDOFF_BITS = $clog2(HOLDOFF_CLOCKS)+1;
    wire [NBEAMS-1:0] trigger_signal_bit_o;
    wire[NBEAMS-1:0][31:0] trigger_count_out;
    reg [NBEAMS-1:0][HOLDOFF_BITS-1:0] holdoff_delay = {(NBEAMS*HOLDOFF_BITS){1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 31'h0; // Pass back trigger count information

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBEAMS-1:0][31:0] trigger_count_wb_reg; // Pass back # of triggers on WB

    (* CUSTOM_CC_SRC = CLKTYPE *) // If the timing fails, try again with this (changed to src)
    reg [NBEAMS-1:0][31:0] trigger_count_reg; // Pass back # of triggers on WB



    // Wishbone connection split between AGC, Biquads, and Trigger Rate
    // Use bits 14 and 13 to differentiate, 00 for AGC, 01 for Biquad, 10 for Trigger Rate
    // These interfaces are host-named (M). Sine the ports of this module are target-named,
    // there needs to be crossover
    `DEFINE_WB_IF( agc_submodule_ , 22, 32);
    `DEFINE_WB_IF( bq_submodule_ , 22, 32);


    //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[13]) ? bq_submodule_ack_i : agc_submodule_ack_i;
    assign wb_err_o = (wb_adr_i[13]) ? bq_submodule_err_i : agc_submodule_err_i;
    assign wb_rty_o = (wb_adr_i[13]) ? bq_submodule_rty_i : agc_submodule_rty_i;
    assign wb_dat_o = (wb_adr_i[13]) ? bq_submodule_dat_i : agc_submodule_dat_i;


    assign wb_threshold_ack_o = (state == ACK);
    assign wb_threshold_err_o = 1'b0;
    assign wb_threshold_rty_o = 1'b0;
    assign wb_threshold_dat_o = response_reg;

    assign agc_submodule_cyc_o = wb_cyc_i && !wb_adr_i[13];
    assign bq_submodule_cyc_o = wb_cyc_i && wb_adr_i[13];
    
    assign agc_submodule_stb_o = wb_stb_i;
    assign bq_submodule_stb_o = wb_stb_i;
    assign agc_submodule_adr_o = wb_adr_i;
    assign bq_submodule_adr_o = wb_adr_i;
    assign agc_submodule_dat_o = wb_dat_i;
    assign bq_submodule_dat_o = wb_dat_i;
    assign agc_submodule_we_o = wb_we_i;
    assign bq_submodule_we_o = wb_we_i;
    assign agc_submodule_sel_o = wb_sel_i;
    assign bq_submodule_sel_o = wb_sel_i;


    ////////////////////////////////////////////////////////
    //////        Wishbone FSM stolen from AGC        //////
    ////////////////////////////////////////////////////////

    // (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the thresholds here
    reg [NBEAMS-1:0][17:0] threshold_regs = {(NBEAMS*18){1'b0}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [17:0] threshold_writing = {18{1'b0}};
    // reg  [NBEAMS-1:0] trigger_threshold_written_aclk = 1'b0;
    // reg  [NBEAMS-1:0] trigger_threshold_written_wbclk = 1'b0;

    reg  [NBEAMS-1:0] trigger_threshold_ce = {NBEAMS{1'b0}};
    wire [NBEAMS-1:0] trigger_threshold_ce_aclk;


    // flag_sync u_CE_flag(.in_clkA(trigger_threshold_written_aclk),.clkA(aclk),
    //                     .out_clkB(trigger_threshold_written_wbclk),.clkB(wb_clk_i));

    // Update all thresholds
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg trigger_threshold_update = 0;
    wire trigger_threshold_update_aclk;
    flag_sync u_update_flag(.in_clkA(trigger_threshold_update),.clkA(wb_clk_i),
                            .out_clkB(trigger_threshold_update_aclk),.clkB(aclk));

    // Request trigger count
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg req_trigger_count = 0;
    wire trigger_count_aclk;
    flag_sync u_tick_flag(.in_clkA(req_trigger_count),.clkA(wb_clk_i),
                          .out_clkB(trigger_count_aclk),.clkB(aclk));

    // Mark the trigger count as completed
    reg  trigger_count_done = 0;
    wire trigger_count_done_aclk;
    wire trigger_count_done_wbclk;
    flag_sync u_done_flag(.in_clkA(trigger_count_done_aclk),.clkA(aclk),
                          .out_clkB(trigger_count_done_wbclk),.clkB(wb_clk_i));



    // Trigger rate sampling period control
    reg trigger_count_ce = 0; // Clock enable for counting out the 375 MHz clock
    wire trigger_time_done; // Signal that the trigger counting period is over
    always @(posedge aclk) begin
        if (trigger_count_aclk) trigger_count_ce <= 1'b1; // If you see a flag to start, enable clock
        else if (trigger_time_done) trigger_count_ce <= 1'b0; // If the period is over, stop counting
    end        
    // Move trigger_time_done to trigger_count_done_aclk, with a delay of 6 aclks
    reg [5:0] trigger_done_delay = {6{1'b0}};
    always @(posedge aclk) trigger_done_delay <= { trigger_done_delay[4:0], trigger_time_done };
    assign trigger_count_done_aclk = trigger_done_delay[5];

    // This is where we will count out the clocks in our trigger sampling period (shared by all beams) 
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                .FIXED_TCOUNT_VALUE(TRIGGER_CLOCKS),
                                .HALT_AT_TCOUNT("TRUE"))
        u_trigger_timer(.clk_i(aclk),
                        .rst_i(trigger_count_aclk), // Reset the counter with new request flag
                        .count_i(trigger_count_ce),
                        .tcount_reached_o(trigger_time_done));


    genvar beam_idx;
    generate
        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin : CE_FLAGS_AND_THRESHOLD  
            // Flag to clock enable for a specific beam threshold load in
            flag_sync u_CE_flag(.in_clkA(trigger_threshold_ce[beam_idx]),.clkA(wb_clk_i),
                                .out_clkB(trigger_threshold_ce_aclk[beam_idx]),.clkB(aclk));     

            // Increment the counter if there is a trigger and not in holdoff
            always @(posedge aclk) begin
                
                if(trigger_count_aclk) begin // Reset for a new count
                    trigger_count_reg[beam_idx] <= 0;
                    holdoff_delay[beam_idx] <= 0; // reset the holdoff
                end else if(trigger_count_ce && trigger_signal_bit_o[beam_idx] && (holdoff_delay[beam_idx]==0)) begin
                    trigger_count_reg[beam_idx] <= trigger_count_reg[beam_idx] + 1;
                    holdoff_delay[beam_idx] <= HOLDOFF_CLOCKS; // Begin the holdoff
                end else if(holdoff_delay[beam_idx]>0) begin
                    holdoff_delay[beam_idx] <= holdoff_delay[beam_idx] - 1; // Count down from last trigger count
                end
            end
        end
    endgenerate

    wire [7:0] beam_idx_adr = wb_threshold_adr_i[9:2]; // Used to select which beam we are working on

    // Moving this outside to please synthesizer
    // Stage a threshold in for a specific beam
    always @(posedge wb_clk_i) begin
    //  ------->                                                           0x800
        if((state == IDLE) && (wb_threshold_cyc_i && wb_threshold_stb_i && wb_threshold_adr_i[11] && wb_threshold_we_i && wb_threshold_sel_i[1] && wb_threshold_dat_i[0]))
        begin
            trigger_threshold_ce[beam_idx_adr] <= 1'b1;
            threshold_writing <= threshold_regs[beam_idx_adr];
        end else begin
            trigger_threshold_ce[beam_idx_adr] <= 1'b0;
        end
    end

    always @(posedge wb_clk_i) begin
        if (req_trigger_count) trigger_count_done <= 0;
        else if (trigger_count_done_wbclk) trigger_count_done <= 1;
        
        if (trigger_count_done_wbclk) begin // flag that a counting cycle just completed
            trigger_count_wb_reg <= trigger_count_reg; // Contains all results
        end            

        // Write command flags. These handle writes to address 0x00.
        req_trigger_count <= (state == IDLE) && (wb_threshold_cyc_i && wb_threshold_stb_i && `ADDR_MATCH( wb_threshold_adr_i, 10'h000, THRESHOLD_MASK ) && wb_threshold_we_i && wb_threshold_sel_i[0] && wb_threshold_dat_i[0]);
        trigger_threshold_update <= (state == IDLE) && (wb_threshold_cyc_i && wb_threshold_stb_i && `ADDR_MATCH( wb_threshold_adr_i, 10'h000, THRESHOLD_MASK ) && wb_threshold_we_i && wb_threshold_sel_i[1] && wb_threshold_dat_i[1]);

        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_threshold_cyc_i && wb_threshold_stb_i) begin
                if (wb_threshold_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= DELAY; // The delay is to let the the delayed threshold_CE complete the clock crossing
            DELAY: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here, but there arae more bits than states
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            if(wb_threshold_adr_i[10]) begin 
                response_reg <= trigger_count_wb_reg[wb_threshold_adr_i[9:2]];
            end
            else if (wb_threshold_adr_i[11]) begin
                response_reg <= {{14{1'b0}}, {threshold_regs[wb_threshold_adr_i[9:2]]}}; // Threshold is 18 bits
            end
            else begin
                response_reg <= {{31{1'b0}}, {trigger_count_done}};
            end
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            if (wb_threshold_adr_i[10]) begin // The 8th bit is used to indicate a threshold write
                if (wb_threshold_sel_i[0]) threshold_regs[wb_threshold_adr_i[9:2]][7:0] <= wb_threshold_dat_i[7:0];
                if (wb_threshold_sel_i[1]) threshold_regs[wb_threshold_adr_i[9:2]][15:8] <= wb_threshold_dat_i[15:8];
                if (wb_threshold_sel_i[2]) threshold_regs[wb_threshold_adr_i[9:2]][17:16] <= wb_threshold_dat_i[17:16];
            end             
        end
    end

    // TODO: Check about this clock crossing //L
    assign trigger_count_out = trigger_count_reg;

    wire  [7:0][39:0] data_stage_connection;
    wire  [7:0][39:0] data_stage_debug;
    
    `ifdef USING_DEBUG
    assign dat_o = data_stage_connection;
    assign dat_debug = data_stage_debug;
    `endif

    trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
                u_chain(
                    .wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    // `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
                    // `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
                    `CONNECT_WBS_IFM( wb_bq_ , bq_submodule_ ),//L
                    `CONNECT_WBS_IFM( wb_agc_ , agc_submodule_ ),
                    .reset_i(reset_i), 
                    .aclk(aclk),
                    .dat_i(dat_i),
                    `ifdef USING_DEBUG
                    .dat_debug(dat_debug),
                    `endif
                    .dat_o(data_stage_connection));

    generate
        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin 
            assign trigger_o[beam_idx] = trigger_signal_bit_o[beam_idx] && !(|holdoff_delay[beam_idx]);// holdoff_delay
        end
    endgenerate

    beamform_trigger #(.NBEAMS(NBEAMS)) 
        u_trigger(
            .clk_i(aclk),
            .data_i(data_stage_connection),

            .thresh_i(threshold_writing),
            .thresh_ce_i(trigger_threshold_ce_aclk),
            .update_i(trigger_threshold_update_aclk),        
            
            .trigger_o(trigger_signal_bit_o));



endmodule
