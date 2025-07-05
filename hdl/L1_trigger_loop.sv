`timescale 1ns/1ps
`include "interfaces.vh"

`ifndef DLYFF
`define DLYFF #0.1
`endif

`define STARTTHRESH 18'd4500
module L1_trigger_loop #(parameter WBCLKTYPE = "NONE",
                         parameter CLKTYPE = "NONE",
                         parameter NBEAMS = 48,
                         parameter COUNT_MARGIN = 2)(
        input wb_clk_i,                                         
        // this is what takes us out of reset_start.
        input loop_enable_i,
        output reset_complete_o,
        
        // state change request interface
        input [1:0] loop_state_req_i,                       
        output [1:0] loop_state_o,
        
        input [31:0] target_rate_i,
        input [15:0] target_delta_i,
        
        // manual threshold update interface and readback
        input [31:0] thresh_dat_i,
        input [5:0] thresh_idx_i,
        // the ack here acks both of 'em
        input thresh_upd_i,
        input thresh_wr_i,
        output thresh_ack_o,
        output [17:0] thresh_dat_o,
        
        // scaler read interface
        input [5:0] scal_idx_i,
        output [31:0] scal_dat_o,
                
        // wishbone to submodules        
        `HOST_NAMED_PORTS_WB_IF( loop_ , 22, 32 ),
        // timer
        input trig_count_done_i
    );
    // ease decode. this is magic shit yo
    localparam NBEAMS_LOG2 = $clog2(NBEAMS);
    // clog2(48) is 6. 1<<6 is 64.
    localparam NBEAMS_CEIL_POW2 = (1<<NBEAMS_LOG2);
    // and this would be 32
    localparam NBEAMS_LESS_POW2 = (1<<(NBEAMS_LOG2-1));
                         
    // only 3 loop states now: reset, run, stop, pause
    // reset -> run : do normal stuff
    // reset -> pause : only update rates
    // reset -> stop : go to stop (manual updates, no rate updates)
    // run -> reset : finish the current operation then jump to reset and stop there
    // run -> stop : finish the current update and stop (manual updates)
    // run -> pause : finish the current update, continue updating rates
    // stop -> reset : go to reset
    // stop -> run : go do normal stuff
    // stop -> pause : update rates
    // pause -> reset : go to reset

    // so to do manual crap you need to bounce between STOP and PAUSE
    // just easier this way

    // manual update attempts in reset pause or running states will just be
    // acked pointlessly.
    localparam LOOP_BITS = 2;
    localparam [LOOP_BITS-1:0] LOOP_RESET = 0;
    localparam [LOOP_BITS-1:0] LOOP_RUN = 1;
    localparam [LOOP_BITS-1:0] LOOP_STOP = 2;    
    localparam [LOOP_BITS-1:0] LOOP_PAUSE = 3;
    
    reg [1:0] loop_state = LOOP_RESET;
    // ok : our overall path looks like
    //
    // reset -> 
    //     clear all registers sequentially,
    //     then jump to the update path, then jump to idle
    // run ->
    //     scaler read, threshold calculate, update everyone loop
    // stop ->
    //     wait for manual writes and updates
    // pause ->
    //     scaler read, loop
    // state transitions only happen in idle
    // we only exit reset start if enabled
    localparam FSM_BITS = 5;
    localparam [FSM_BITS-1:0] RESET_START = 0;
    localparam [FSM_BITS-1:0] RESETTING = 1;
    localparam [FSM_BITS-1:0] RESET_PREP_WRITE = 2;
    localparam [FSM_BITS-1:0] RESET_COMPLETE = 3;
    localparam [FSM_BITS-1:0] IDLE = 4;
    localparam [FSM_BITS-1:0] COUNT_START = 5;
    localparam [FSM_BITS-1:0] COUNT_WAIT = 6;
    localparam [FSM_BITS-1:0] COUNT_READ = 7;
    localparam [FSM_BITS-1:0] THRESHOLD_CALCULATE = 8;
    localparam [FSM_BITS-1:0] COUNT_BEAM_INCREMENT = 9;
    localparam [FSM_BITS-1:0] THRESHOLD_WRITE = 10;
    localparam [FSM_BITS-1:0] THRESHOLD_WRITE_WAIT = 11;
    localparam [FSM_BITS-1:0] THRESHOLD_APPLY = 12;
    localparam [FSM_BITS-1:0] THRESHOLD_BEAM_INCREMENT = 13;
    localparam [FSM_BITS-1:0] THRESHOLD_UPDATE = 14;
    localparam [FSM_BITS-1:0] STOP_PREP = 15;
    
    reg [FSM_BITS-1:0] state = RESET_START;

    wire cyc = (state == COUNT_START ||
                state == COUNT_READ ||
                state == THRESHOLD_WRITE ||
                state == THRESHOLD_APPLY ||
                state == THRESHOLD_UPDATE);
    wire we =  (state == COUNT_START ||
                state == THRESHOLD_WRITE ||
                state == THRESHOLD_APPLY ||
                state == THRESHOLD_UPDATE);

    // harder, need to prep them prior
    reg [21:0] adr = {22{1'b0}};
    reg [31:0] dat = {32{1'b0}};

    reg reset_is_complete = 0;

    // we start at 47 and count DOWN and then when we drop below 0 we're done    
    reg [6:0] beam_idx = NBEAMS-1;
    wire beam_loop_complete = beam_idx[6];
   
    // let synthesizer just infer this        
    // PLEASE let this goddamn thing work to be inferred.
    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated thresholds here
    reg [NBEAMS-1:0][17:0] threshold_recalculated_regs = {NBEAMS{`STARTTHRESH}};
   
    reg [17:0] threshold_tmp = {18{1'b0}};

    // but hardcode the scaler RAM to make things easier
    wire scaler_ram_we;
    wire [5:0] scaler_ram_waddr;
    wire [31:0] scaler_ram_wdata;    
    wire [31:0] scaler_ram_curdata;   
    // ease decode
    wire [NBEAMS_CEIL_POW2-1:0][17:0] threshold_regs_exp;

    // god damnit, the stupid-ass RAM64X1D somehow effs up
    // try the macro
    
    xpm_memory_dpdistram #(.ADDR_WIDTH_A(6),
                           .ADDR_WIDTH_B(6),
                           .MEMORY_SIZE(2048),
                           .READ_LATENCY_A(0),
                           .READ_LATENCY_B(0),
                           .WRITE_DATA_WIDTH_A(32),
                           .READ_DATA_WIDTH_A(32),
                           .READ_DATA_WIDTH_B(32))
        u_sram( .addra(scaler_ram_waddr),
                .addrb(scal_idx_i),
                .clka(wb_clk_i),
                .dina(scaler_ram_wdata),
                .douta(scaler_ram_curdata),
                .doutb(scal_dat_o),
                // i don't think anything else matters
                .ena(scaler_ram_we),
                .wea(scaler_ram_we),
                .enb(1'b1));    
    generate
        genvar i;
//      genvar j;
//        for (j=0;j<32;j=j+1) begin : RAM
//            RAM64X1D u_ram(.WCLK(wb_clk_i),
//                           .WE(scaler_ram_we),
//                           .A(scaler_ram_waddr),
//                           .DPRA(scal_idx_i),
//                           .D(scaler_ram_wdata[j]),
//                           .SPO(scaler_ram_curdata[j]),
//                           .DPO(scal_dat_o[j]));
//        end
        for (i=0;i<NBEAMS_CEIL_POW2;i=i+1) begin : MAP
            if (i < NBEAMS) begin : R
                assign threshold_regs_exp[i] = threshold_recalculated_regs[i];
            end else begin : S
                assign threshold_regs_exp[i] = threshold_recalculated_regs[i-NBEAMS_LESS_POW2];
            end                
        end
    endgenerate        

    assign scaler_ram_waddr = beam_idx[4:0];
    assign scaler_ram_we = (state == COUNT_READ && loop_ack_i);    
    assign scaler_ram_wdata = loop_dat_i;
    
    wire [5:0] cur_beam = (loop_state == LOOP_STOP) ? thresh_idx_i : beam_idx[5:0];

    always @(posedge wb_clk_i) begin
        // note that we only exit IDLE if these two are equal
        if (state == IDLE)
            loop_state <= `DLYFF loop_state_req_i;

        if (state == RESET_COMPLETE)
            reset_is_complete <= `DLYFF 1;
        else if (loop_state_req_i == LOOP_RESET)
            reset_is_complete <= `DLYFF 0;
            
        case (state)
            RESET_START: if (loop_enable_i) state <= `DLYFF RESETTING;
            RESETTING: if (beam_loop_complete) state <= `DLYFF RESET_PREP_WRITE;
            RESET_PREP_WRITE: state <= `DLYFF THRESHOLD_WRITE;
            RESET_COMPLETE: if (loop_state_req_i != LOOP_RESET) state <= `DLYFF IDLE;
            IDLE: if (loop_state_req_i == loop_state) begin
                      if (loop_state == LOOP_RESET) 
                        state <= `DLYFF RESET_START;
                      else if (loop_state == LOOP_RUN || loop_state == LOOP_PAUSE)
                        state <= `DLYFF COUNT_START;
                      else if (loop_state == LOOP_STOP) begin
                            if (thresh_upd_i || thresh_wr_i) 
                                state <= `DLYFF STOP_PREP;
                      end
                   end
            COUNT_START: if (loop_ack_i) state <= `DLYFF COUNT_WAIT;
            COUNT_WAIT: if (trig_count_done_i) state <= `DLYFF COUNT_READ;
            COUNT_READ: if (loop_ack_i) begin
                            if (loop_state == LOOP_RUN) state <= `DLYFF THRESHOLD_CALCULATE;
                            else state <= `DLYFF COUNT_BEAM_INCREMENT;
                        end                            
            THRESHOLD_CALCULATE: state <= `DLYFF COUNT_BEAM_INCREMENT;
            // The sleaze here gives time for the beam index to reset.
            // clk  state                       beam_idx
            // 0    THRESHOLD_CALCULATE         0000000
            // 1    COUNT_BEAM_INCREMENT        1111111
            // 2    THRESHOLD_BEAM_INCREMENT    47
            // 3    THRESHOLD_WRITE             47
            COUNT_BEAM_INCREMENT: if (beam_loop_complete) begin
                                    if (loop_state == LOOP_PAUSE) state <= `DLYFF IDLE;
                                    else state <= `DLYFF THRESHOLD_BEAM_INCREMENT;
                                  end else state <= COUNT_READ;
            THRESHOLD_WRITE: if (loop_ack_i) state <= `DLYFF THRESHOLD_WRITE_WAIT;
            THRESHOLD_WRITE_WAIT: state <= `DLYFF THRESHOLD_APPLY;
            THRESHOLD_APPLY: if (loop_ack_i) begin
                                if (loop_state == LOOP_STOP) state <= `DLYFF IDLE;
                                else state <= `DLYFF THRESHOLD_BEAM_INCREMENT;
                             end
            THRESHOLD_BEAM_INCREMENT: if (beam_loop_complete) state <= `DLYFF THRESHOLD_UPDATE;
                                      else state <= `DLYFF THRESHOLD_WRITE;
            THRESHOLD_UPDATE: if (loop_ack_i) begin
                                if (loop_state == LOOP_RESET) state <= `DLYFF RESET_COMPLETE;
                                else state <= `DLYFF IDLE;
                              end
            // jumping to THRESHOLD_BEAM_INCREMENT buys us the clock needed
            // so that the RAM output updates
            STOP_PREP: if (thresh_upd_i) state <= `DLYFF THRESHOLD_UPDATE;
                       else state <= `DLYFF THRESHOLD_BEAM_INCREMENT;                              
        endcase

        if (state == RESET_START || state == IDLE || beam_loop_complete)
            beam_idx <= `DLYFF NBEAMS-1;
        else if ((state == THRESHOLD_CALCULATE ||
                 (state == THRESHOLD_APPLY && loop_ack_i) ||
                 (state == RESETTING)))
            beam_idx <= `DLYFF beam_idx - 1;                 

        // address demultiplexing
        if (state == IDLE) 
            adr <= `DLYFF 22'h0;        // control register for start
        else if (state == COUNT_WAIT || 
                 state == COUNT_BEAM_INCREMENT ||
                 state == RESET_PREP_WRITE ||
                 state == THRESHOLD_BEAM_INCREMENT && !beam_loop_complete)
            adr <= `DLYFF { {10{1'b0}}, 4'h4, cur_beam[5:0], 2'b00 }; // threshold register
        else if (state == THRESHOLD_WRITE_WAIT)
            adr <= `DLYFF { {10{1'b0}}, 4'h8, cur_beam[5:0], 2'b00 }; // CE register        
        else if (state == THRESHOLD_BEAM_INCREMENT && beam_loop_complete)
            adr <= `DLYFF 22'h0;        // control register for update
        else if (state == STOP_PREP) begin
            if (thresh_upd_i) adr <= `DLYFF 22'h0;
            else adr <= `DLYFF { {10{1'b0}}, 4'h4, cur_beam[5:0], 2'b00 }; // threshold register
        end            

        // data demultiplexing
        // don't need to do anything in COUNT_BEAM_INCREMENT because it jumps through
        // THRESHOLD_BEAM_INCREMENT
        if (state == IDLE || state == THRESHOLD_WRITE_WAIT)
            dat <= `DLYFF 32'h1;   // start or CE
        else if ((state == THRESHOLD_BEAM_INCREMENT && beam_loop_complete) ||
                (state == STOP_PREP && thresh_upd_i))
            dat <= `DLYFF 32'h2; // update                       
        else if (state == RESET_PREP_WRITE || 
                 (state == STOP_PREP && !thresh_upd_i) ||
                 (state == THRESHOLD_BEAM_INCREMENT && !beam_loop_complete))
            dat <= `DLYFF threshold_regs_exp[cur_beam]; // threshold

        if (state == RESET_START)
            threshold_tmp <= `DLYFF `STARTTHRESH;            
        else begin
            if (state == COUNT_READ) begin
                if (!loop_ack_i) threshold_tmp <= `DLYFF threshold_recalculated_regs[beam_idx[5:0]];
                else if (loop_dat_i < target_rate_i + COUNT_MARGIN) threshold_tmp <= `DLYFF threshold_tmp + target_delta_i;
                else if (loop_dat_i > target_rate_i + COUNT_MARGIN) threshold_tmp <= `DLYFF threshold_tmp - target_delta_i; 
            end else if (state == IDLE && thresh_wr_i)
                threshold_tmp <= `DLYFF thresh_dat_i;
        end
        // update the RAM
        if (state == THRESHOLD_CALCULATE || state == RESETTING || (state == STOP_PREP && thresh_wr_i))
            threshold_recalculated_regs[cur_beam] <= `DLYFF threshold_tmp;
    end

    assign loop_cyc_o = cyc;
    assign loop_stb_o = cyc;
    assign loop_adr_o = adr;
    assign loop_dat_o = dat;
    assign loop_we_o = we;
    assign loop_sel_o = 4'hF;

    assign reset_complete_o = reset_is_complete;
    assign loop_state_o = loop_state;
    
    assign thresh_dat_o = threshold_regs_exp[thresh_idx_i];
    // we can ack in STOP_PREP because even though it takes longer, we capture the address immediately
    assign thresh_ack_o = (state == STOP_PREP);
    
endmodule
