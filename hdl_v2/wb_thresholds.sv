`timescale 1ns / 1ps
`include "interfaces.vh"
// This is the WISHBONE threshold space.
// It splits entirely into two: an upper control space
// starting at 0x1000, and the lower threshold space
// at 0x0000-0x0FFF.
// Most of the threshold space is shadowed:
// the primary thresholds are at 0x000 - 0x7FF
// and the subthresholds are at  0x800 - 0xFFF
//
//
// NOTE NOTE NOTE: If this can't meet timing, swap the threshold
// outputs to IFCLK and rebuffer in aclk. You can recapture
// in aclk (see sec 7.1.4) using aclk_phase. Buffer it twice
// (aclk_phase -> FF -> FF )
//                      ^--- use this signal as "capture"
// and capture thresh_wr[1:0] <= {2{capture}} & thresh_wr_i;
//             thresh_update[1:0] <= {2{capture}} & thresh_update_i;
//             if (thresh_wr[0] && capture) thresh_dat[0] <= thresh_dat_i[0];
//             if (thresh_wr[1] && capture) thresh_dat[1] <= thresh_dat_i[1];
// and then tag signals in the sending domain with CUSTOM_MC_SRC_TAG = "THRESHOLDS"
//                                                 CUSTOM_MC_MIN = "0.0"
//                                                 CUSTOM_MC_MAX = "1.0"
// (this seems silly but the custom multicycle tools use source clock timing)
//
// Our address space is only 12 bits because we share it with the scalers,
// even though we have a control register for scalers to allow us to synchronize
// in the WISHBONE space if we reaaallly care
//
// wb_adr_i[12] splits between control(1) and thresholds(0)
module wb_thresholds #(parameter WBCLKTYPE = "NONE",
                       parameter ACLKTYPE = "NONE",
                       parameter DEFAULT_COUNT = 100000000,
                       parameter NBEAMS = 46)(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 12, 32 ),
        
        input scal_bank_i,
        output scal_timer_o,
        output scal_rst_o,
        input aclk,
        output [18*2-1:0] thresh_o,
        output [1:0] thresh_wr_o,
        output [1:0] thresh_update_o
    );

    wire [7:0] ram_wraddr = {wb_adr_i[3 +: 6], wb_adr_i[10], wb_adr_i[2]};
    wire [31:0] ram_wrdata = { {14{1'b0}}, wb_dat_i[0 +: 18] };
    wire [31:0] ram_wr_readback;

    wire ram_wr;

    wire sel_thresholds = !wb_adr_i[11];
    wire sel_control = wb_adr_i[11];
    // 4 control registers:
    // 0 threshold reset/update/status
    // 1 scaler status and reset
    // 2 scaler period adjustment and readback
    //   NOTE NOTE NOTE: the scaler period adjustment is weird, you WRITE the adjustment you want and you GET the total period.
    //   Period always starts off at 1 second. Adjustment is a 32-bit signed integer.
    // 3 reserved
    wire [31:0] control_regs[3:0];        
    // only pick off [3:2] of this
    localparam [15:0] THRESH_CONTROL = 16'h1800;    // in *our* distorted space, this is 800
    localparam [15:0] SCALER_CONTROL = 16'h1804;    // in *our* distorted space, this is 804
    localparam [15:0] SCALER_ADJUST =  16'h1808;    // in *our* distorted space, this is 808
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg reset_update = 0;
    (* CUSTOM_CC_DST = ACLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] reset_update_aclk = {2{1'b0}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg update_requested = 0;

    (* CUSTOM_CC_DST = ACLKTYPE, ASYNC_REG = "TRUE" *)
    reg [2:0] update_requested_aclk = {3{1'b0}};
    reg do_update = 0;

    (* CUSTOM_CC_DST = WBCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [2:0] update_finished_wbclk = {3{1'b0}};
    (* CUSTOM_CC_SRC = ACLKTYPE *)
    reg update_finished = 1'b0;

    reg scaler_write_bank = 0;
    reg scaler_reset = 0;
    

    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] RAM_READ = 1;
    localparam [FSM_BITS-1:0] RAM_WAIT_0 = 2;
    localparam [FSM_BITS-1:0] CAPTURE = 3;
    localparam [FSM_BITS-1:0] ACK = 4;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg [31:0] wb_dat = {32{1'b0}};
    wire [31:0] scaler_period;

    wire scaler_adjust_wr = (state == ACK && sel_control && wb_adr_i[3:2] == SCALER_ADJUST[3:2] && wb_we_i);    

    assign control_regs[0] = { {30{1'b0}}, update_requested, reset_update };
    assign control_regs[1] = { {30{1'b0}}, scaler_write_bank, scaler_reset };
    assign control_regs[2] = scaler_period;
    assign control_regs[3] = control_regs[1];
        
    always @(posedge wb_clk_i) begin
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                if (!wb_we_i) begin
                    if (sel_thresholds) state <= RAM_READ;
                    else state <= CAPTURE;
                end else state <= ACK;                
            end
            RAM_READ: state <= RAM_WAIT_0;
            RAM_WAIT_0: state <= CAPTURE;
            CAPTURE: state <= ACK;
            ACK: state <= IDLE;
        endcase

        if (state == CAPTURE) begin
            if (sel_thresholds) wb_dat <= ram_wr_readback;
            else if (sel_control) wb_dat <= control_regs[wb_adr_i[3:2]];            
        end
        if (state == ACK && wb_we_i && sel_control && wb_adr_i[3:2] == THRESH_CONTROL[3:2]) begin
            if (wb_sel_i[0]) begin
                reset_update <= wb_dat_i[0];
            end
        end 
        if (update_finished_wbclk[1] && !update_finished_wbclk[2]) begin
            update_requested <= 0;
        end else if (state == ACK && wb_we_i && sel_control && wb_adr_i[3:2] == THRESH_CONTROL[3:2]) begin
            if (wb_sel_i[0]) begin
                update_requested <= wb_dat_i[1];
            end                
        end
        if (state == ACK && wb_we_i && sel_control && wb_adr_i[3:2] == SCALER_CONTROL[3:2]) begin
            if (wb_sel_i[0]) scaler_reset <= wb_dat_i[0];
        end

        scaler_write_bank <= scal_bank_i;
    end

    preset_timer #(.DEFAULT_COUNT(DEFAULT_COUNT),.WIDTH(32))
        u_scal_timer(.clk_i(wb_clk_i),
                     .rst_i(scaler_reset),
                     .max_count_i(wb_dat_i),
                     .max_count_o(scaler_period),
                     .ce_i(1'b1),
                     .max_count_wr_i(scaler_adjust_wr),
                     .count_reached_o(scal_timer_o));

    assign ram_wr = (state == ACK && sel_thresholds && wb_we_i);
    assign scal_rst_o = scaler_reset;
    
    // no matter what we have to update NDUALBEAMS
    // things, because even though the last DSP might
    // be half used it still exists.
    localparam NDUALBEAMS = (NBEAMS/2) + (NBEAMS%2);
    localparam NUM_THRESH = NDUALBEAMS*2;
    localparam COUNTER_WIDTH = $clog2(NUM_THRESH);
    
    // timing (NUM_THRESH = 46)
    // clk  state                   read    dat     addr    storage next_write
    // 0    UPDATE_IDLE             0       X       45      X       X
    // 1    READ_PREP_0             1       X       45      X       X
    // 2    READ_PREP_1             1       X       44      X       X
    // 3    READ_SUBTHRESH          1       MEM[45] 43      X       X
    // 4    READ_TRIG               1       MEM[44] 42      MEM[45] X
    // 5    WSRN                    1       MEM[43] 41      MEM[44] MEM[44]-MEM[45]
    // 6    WTRN                    1       MEM[42] 40      MEM[43] MEM[44]
    // ..
    // 44   WTRN                    1       MEM[04] 2       MEM[05] MEM[06]
    // 45   WSRN                    1       MEM[03] 1       MEM[04] MEM[04]-MEM[05]
    // 46   WTRN                    1       MEM[02] 0       MEM[03] MEM[04]
    // 47   WRITE_SUBTHRESH         0       MEM[01] -1      MEM[02] MEM[02]-MEM[03]
    // 48   WRITE_TRIG              0       MEM[00] -1      MEM[01] MEM[02]
    // 49   WRITE_LAST_SUBTHRESH    0       X       -1      MEM[00] MEM[00]-MEM[01]
    // 50   WRITE_LAST_TRIG         0       X       -1      XX      MEM[00]
    // 
    // Threshold space.
    localparam UFSM_BITS = 4;
    localparam [UFSM_BITS-1:0] UPDATE_IDLE = 0;
    localparam [UFSM_BITS-1:0] READ_PREP_0 = 1;     // assert read
    localparam [UFSM_BITS-1:0] READ_PREP_1 = 2;     // latency
    localparam [UFSM_BITS-1:0] READ_SUBTHRESH = 3;   // capture subthresh
    localparam [UFSM_BITS-1:0] READ_TRIG = 4;  // capture trig
    localparam [UFSM_BITS-1:0] WRITE_SUBTHRESH_READ_NEXT = 5;   // write subthresh, read next one
    localparam [UFSM_BITS-1:0] WRITE_TRIG_READ_NEXT = 6;   // write trig, read next one
    localparam [UFSM_BITS-1:0] WRITE_SUBTHRESH = 7;
    localparam [UFSM_BITS-1:0] WRITE_TRIG = 8;
    localparam [UFSM_BITS-1:0] WRITE_LAST_SUBTHRESH = 9;
    localparam [UFSM_BITS-1:0] WRITE_LAST_TRIG = 10;
    reg [UFSM_BITS-1:0] ustate = UPDATE_IDLE;

    reg threshold_update = 0;
        
    wire threshold_write = (ustate == WRITE_SUBTHRESH_READ_NEXT ||
                            ustate == WRITE_TRIG_READ_NEXT ||
                            ustate == WRITE_SUBTHRESH ||
                            ustate == WRITE_TRIG ||
                            ustate == WRITE_LAST_SUBTHRESH ||
                            ustate == WRITE_LAST_TRIG);
    wire ram_read = (ustate == READ_PREP_0 ||
                     ustate == READ_PREP_1 ||
                     ustate == READ_SUBTHRESH ||
                     ustate == READ_TRIG ||
                     ustate == WRITE_SUBTHRESH_READ_NEXT ||
                     ustate == WRITE_TRIG_READ_NEXT);
    reg [1:0][17:0] storage = {18*2{1'b0}};
    reg [1:0][17:0] next_write = {18*2{1'b0}};

    // start at the last address, which is actually a subthreshold
    // we need to decrement every other, so in READ_PREP_0, READ_SUBTHRESH,
    // then WRITE_SUBTHRESH_READ_NEXT.
    reg [COUNTER_WIDTH-1:0] beam_counter = NUM_THRESH-1;
    wire [COUNTER_WIDTH:0] beam_counter_minus_one = beam_counter - 1;
    wire loop_complete = beam_counter_minus_one[COUNTER_WIDTH];
    
    wire [63:0] ram_out;
    wire reset_the_update = (reset_update_aclk[1]);

    // Our threshold RAM needs to be 128x64 minimum.
    // On the WISHBONE side, it is written in 32 bits at a time.
    // On the WISHBONE side, it is written 0x800 - 0xBFF = thresholds
    //                                     0xC00 - 0xFFF = subthresholds
    // WISHBONE     threshold       ram write       ram readout
    // 800          beam 0 trig     0               0
    // 804          beam 1 trig     1               0
    // C00          beam 0 subthr   2               1
    // C04          beam 1 subthr   3               1
    // so write addr[0] = wb_adr_i[2]
    //    write addr[1] = wb_adr_i[11]
    //     read addr[0] = beam_counter[0]
    wire [6:0] ram_rdaddr = beam_counter;
    
    always @(posedge aclk) begin
        reset_update_aclk <= { reset_update_aclk[0], reset_update };
        update_requested_aclk <= { update_requested_aclk[1:0], update_requested };

        if (update_requested_aclk[1] && !update_requested_aclk[2])
            do_update <= 1;
        else if (ustate == READ_PREP_0)
            do_update <= 0;

        if (do_update) 
            update_finished <= 0;
        else if (ustate == WRITE_LAST_TRIG)
            update_finished <= 1;
        
        threshold_update <= (ustate == WRITE_LAST_TRIG);
                                                
        if (ustate == READ_SUBTHRESH || 
            ustate == READ_TRIG ||
            ustate == WRITE_SUBTHRESH_READ_NEXT ||            
            ustate == WRITE_TRIG_READ_NEXT ||
            ustate == WRITE_SUBTHRESH ||
            ustate == WRITE_TRIG) begin
            storage[0] <= ram_out[0 +: 18];
            storage[1] <= ram_out[32 +: 18];            
        end
        
        if (ustate == READ_TRIG || 
            ustate == WRITE_TRIG_READ_NEXT ||
            ustate == WRITE_TRIG) begin
            next_write[0] <= ram_out[0 +: 18] - storage[0];
            next_write[1] <= ram_out[32 +: 18] - storage[1];
        end else if (ustate == WRITE_SUBTHRESH_READ_NEXT ||
                     ustate == WRITE_SUBTHRESH ||
                     ustate == WRITE_LAST_SUBTHRESH) begin
            next_write[0] <= storage[0];
            next_write[1] <= storage[1];
        end
        
        if (reset_the_update) 
            beam_counter <= NUM_THRESH-1;
        else if (ustate == READ_PREP_0 ||
                 ustate == READ_PREP_1 ||
                 ustate == READ_SUBTHRESH ||
                 ustate == READ_TRIG ||
                 ustate == WRITE_SUBTHRESH_READ_NEXT ||
                 ustate == WRITE_TRIG_READ_NEXT)
            beam_counter <= beam_counter_minus_one;

        if (reset_the_update) ustate <= UPDATE_IDLE;
        else begin
            case (ustate)
                UPDATE_IDLE: if (do_update) ustate <= READ_PREP_0;
                READ_PREP_0: ustate <= READ_PREP_1;
                READ_PREP_1: ustate <= READ_SUBTHRESH;
                READ_SUBTHRESH: ustate <= READ_TRIG;
                READ_TRIG: ustate <= WRITE_SUBTHRESH_READ_NEXT;
                WRITE_SUBTHRESH_READ_NEXT: ustate <= WRITE_TRIG_READ_NEXT;
                WRITE_TRIG_READ_NEXT: if (loop_complete) ustate <= WRITE_SUBTHRESH;
                                      else ustate <= WRITE_SUBTHRESH_READ_NEXT;
                WRITE_SUBTHRESH: ustate <= WRITE_TRIG;
                WRITE_TRIG: ustate <= WRITE_LAST_SUBTHRESH;
                WRITE_LAST_SUBTHRESH: ustate <= WRITE_LAST_TRIG;
                WRITE_LAST_TRIG: ustate <= UPDATE_IDLE;
            endcase
        end                            
    end
    
    xpm_memory_tdpram #(.ADDR_WIDTH_A(8),
                        .ADDR_WIDTH_B(7),
                        .CLOCKING_MODE("independent_clock"),
                        .BYTE_WRITE_WIDTH_A(32),
                        .BYTE_WRITE_WIDTH_B(64),
                        .MEMORY_SIZE(8192),
                        .READ_DATA_WIDTH_A(32),
                        .WRITE_DATA_WIDTH_A(32),
                        .READ_DATA_WIDTH_B(64),
                        .WRITE_DATA_WIDTH_B(64),
                        .READ_LATENCY_A(2),
                        .READ_LATENCY_B(2))
                        u_thresh_ram(.clka(wb_clk_i),
                                     .sleep(1'b0),
                                     .addra(ram_wraddr),
                                     .ena(state == ACK || state == RAM_READ),
                                     .regcea(1'b1),
                                     .rsta(1'b0),
                                     .douta(ram_wr_readback),
                                     .dina(ram_wrdata),
                                     .wea(ram_wr),
                                     .clkb(aclk),
                                     .regceb(1'b1),
                                     .rstb(1'b0),
                                     .web(1'b0),
                                     .addrb(ram_rdaddr),
                                     .enb(ram_read),
                                     .doutb(ram_out));                        
    
    assign thresh_wr_o = {2{threshold_write}};
    assign thresh_update_o = {2{threshold_update}};
    assign thresh_o = next_write;

    assign wb_ack_o = (state == ACK);
    assign wb_dat_o = wb_dat;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
endmodule
