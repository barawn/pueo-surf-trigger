`timescale 1ns / 1ps
`define DLYFF #0.1
// 12-bit scaler module. This effectively
// uses 0.5 DSPs/scaler, which is double
// what would be needed because we swap
// between DSPs during an update period.
// The DSP usage isn't enough that we care,
// and using the cascade output path allows
// us to avoid a ton of registers and wiring.
//
// If you free-read from this, there's no
// guarantee you'll always be reading the
// same set of data unless you somehow
// sync yourself to the update period.
// 
// According to the XPM docs scal_dat_o should 
// be captured 2 clocks after scal_rd_i.
// Who knows, though.
//
// UPDATED BEAMSCALER MODULE:
// - Instead of splitting the subthresholds off, we instead group
//   them with their primary. This means that we read the same
//   addresses between the primary and subthreshold, and for the v2
//   in python we return a tuple rather than just a single.
//   Splitting the subthresholds off is way harder and more awkward
//   anyway.
module beamscaler_wrap #(parameter NBEAMS = 2,
                         localparam NSCALERS = 2,
                         parameter IFCLKTYPE = "NONE",
                         parameter WBCLKTYPE = "NONE",
                         parameter DEBUG = "FALSE")(
                         
                         input ifclk_i,
                         // These need to be ordered (low half = real)
                         // (upper half = subthreshold)
                         input [NBEAMS*NSCALERS-1:0] count_i,
                         input timer_i,
                         output done_o,
                         
                         input wb_clk_i,
                         input wb_rst_i,
                         // 96 scalers needs 7 bit addr, we make it 8 bits
                         // for safety
                         input scal_rd_i,
                         input [7:0] scal_adr_i,
                         output [31:0] scal_dat_o,
                         output write_bank_o
                         );
    // With the subthresholds now integrated, we don't need multiples of 4
    // anymore - we need NBEAMS/2 rounded up.
    localparam NUM_QSCAL = (NBEAMS/2) + (NBEAMS%2);
 
    // we will do sleaze, and the input will be
    // i/2 and the output will be (i/2+1)%NUM_QSCAL.
    // This actually loops it around but the first beamscaler
    // doesn't connect its input, so it doesn't matter.
    wire [NUM_QSCAL-1:0][48*2-1:0] cascade;
    wire [1:0][47:0] final_out;
    reg [23:0] dsp_capture_A = {24{1'b0}};
    reg [23:0] dsp_capture_B = {24{1'b0}};
    // no matter what we don't have to worry about missing anything here:
    // the A:B inputs are always clocked in, it's only the P registers that won't get clocked.
    // so even if wb_clk_ce goes in PREP_B (so it's in A:B in COMPUTE_A_0) it won't get added
    // to A, but it will get added to B since B's P register gets enabled in COMPUTE_A_0.
    localparam FSM_BITS = 5;                        // state    state_ce    dsp_ce  rstp wra    wrb
    localparam [FSM_BITS-1:0] RESET = 0;            // XXX      00          00      1    0      0
    localparam [FSM_BITS-1:0] RESET_PREP_A  = 1;    // 010      01          00      0    0      0
    localparam [FSM_BITS-1:0] IDLE_A = 2;           // XXX      00          01      0    0      0
    localparam [FSM_BITS-1:0] PREP_B = 3;           // 010      10          01      0    0      0
    localparam [FSM_BITS-1:0] COMPUTE_A_0 = 4;      // 111      01          10      0    0      0
    localparam [FSM_BITS-1:0] COMPUTE_A_1 = 5;      // XXX      00          11      0    0      0
    localparam [FSM_BITS-1:0] DATA_SHIFT_A = 6;     // 001      01          10      0    ->1    0
    localparam [FSM_BITS-1:0] DSP_SHIFT_A = 7;      // XXX      00          11      0    ->1    0
    localparam [FSM_BITS-1:0] IDLE_B = 8;           // XXX      00          10      0    
    localparam [FSM_BITS-1:0] PREP_A = 9;           // 010      01          10      0
    localparam [FSM_BITS-1:0] COMPUTE_B_0 = 10;     // 111      10          01
    localparam [FSM_BITS-1:0] COMPUTE_B_1 = 11;     // XXX      00          11
    localparam [FSM_BITS-1:0] DATA_SHIFT_B = 12;    // 001      10          01
    localparam [FSM_BITS-1:0] DSP_SHIFT_B = 13;     // XXX      00          11
    reg [FSM_BITS-1:0] state = RESET;
    
    // 128 possible addresses. On the write side
    // we have 512 x 72, but really 512 x 64.
    // We write 2x16 per clock, and the byte enables select which bank is being updated.
    // On the read side, the active read bank is the low address.
    reg [7:0] scaler_addr = {8{1'b0}};
    wire [8:0] scaler_addr_minus_one = scaler_addr - 1;
    wire [7:0] scaler_addr_remap = {scaler_addr[6:0], (state==DATA_SHIFT_A || state == DATA_SHIFT_B)};

    reg active_write_bank = 0;

    reg [1:0] scaler_write = {2{1'b0}};

    reg scaler_write_any = 0;        
    // this is combinatoric, it's easier to let Vivado
    // recode the FSM state as needed
    reg [2:0] beamscaler_state;
    wire [1:0] beamscaler_state_ce;
    reg [1:0] beamscaler_ce = 2'b00;
    assign beamscaler_state_ce[0] = (state == RESET_PREP_A) ||
                                    (state == PREP_A)       ||
                                    (state == COMPUTE_A_0)  ||
                                    (state == DATA_SHIFT_A);
    assign beamscaler_state_ce[1] = (state == PREP_B)       ||
                                    (state == COMPUTE_B_0)  ||
                                    (state == DATA_SHIFT_B);
    wire beamscaler_reset = (state == RESET);                                    
    
    always @(*) begin
        (* full_case *)
        case (state)
            RESET_PREP_A: beamscaler_state <= 3'b010;
            PREP_B: beamscaler_state <= 3'b010;
            PREP_A: beamscaler_state <= 3'b010;
            COMPUTE_A_0: beamscaler_state <= 3'b111;
            COMPUTE_B_0: beamscaler_state <= 3'b111;
            DATA_SHIFT_A: beamscaler_state <= 3'b001;
            DATA_SHIFT_B: beamscaler_state <= 3'b001;
        endcase
    end

    reg timer_complete = 0;
    reg update_done = 0;
        
    always @(posedge wb_clk_i) begin
        // this actually does an extra write into the top address, but that's
        // always unused so I *do not care*.
        if (state == RESET || state == IDLE_B) scaler_write[0] <= 0;
        else if (state == DATA_SHIFT_A) scaler_write[0] <= 1;
    
        if (state == RESET || state == IDLE_A) scaler_write[1] <= 0;
        else if (state == DATA_SHIFT_B) scaler_write[1] <= 1;
    
        if (state == RESET || state == IDLE_A || state == IDLE_B) scaler_write_any <= 0;
        else if (state == DATA_SHIFT_A || state == DATA_SHIFT_B) scaler_write_any <= 1;
    

        if (wb_rst_i) timer_complete <= `DLYFF 1'b0;
        else if (timer_i) timer_complete <= `DLYFF 1'b1;
        else if (state == IDLE_A || state == IDLE_B) timer_complete <= `DLYFF 1'b0;

        update_done <= `DLYFF (state == DATA_SHIFT_A || state == DATA_SHIFT_B) && scaler_addr_minus_one[8];
        
        // just transition at the idle points. The read banks are the opposite
        // of this. When we hit the IDLE_A/IDLE_B states, we've fully updated
        // the *other* bank in RAM and in can be read from.
        if (state == IDLE_A) active_write_bank <= `DLYFF 0;
        else if (state == IDLE_B) active_write_bank <= `DLYFF 1;
        
        if (state == IDLE_A || state == IDLE_B)
            scaler_addr <= `DLYFF NUM_QSCAL;
        else if (state == DATA_SHIFT_A || state == DATA_SHIFT_B)
            scaler_addr <= `DLYFF scaler_addr_minus_one;
            
        if (wb_rst_i) state <= `DLYFF RESET;
        else begin
            case (state)
                RESET:  state <= `DLYFF RESET_PREP_A;
                RESET_PREP_A: state <= `DLYFF IDLE_A;
                IDLE_A: if (timer_complete) state <= `DLYFF PREP_B;
                PREP_B: state <= `DLYFF COMPUTE_A_0;
                COMPUTE_A_0: state <= `DLYFF COMPUTE_A_1;
                COMPUTE_A_1: state <= `DLYFF DATA_SHIFT_A;
                DATA_SHIFT_A: if (scaler_addr_minus_one[8]) state <= `DLYFF IDLE_B;
                              else state <= `DLYFF DSP_SHIFT_A;
                DSP_SHIFT_A: state <= `DLYFF DATA_SHIFT_A;
                IDLE_B: if (timer_complete) state <= `DLYFF PREP_A;
                PREP_A: state <= `DLYFF COMPUTE_B_0;
                COMPUTE_B_0: state <= `DLYFF COMPUTE_B_1;
                COMPUTE_B_1: state <= `DLYFF DATA_SHIFT_B;
                DATA_SHIFT_B: if (scaler_addr_minus_one[8]) state <= `DLYFF IDLE_A;
                              else state <= `DLYFF DSP_SHIFT_B;
                DSP_SHIFT_B: state <= `DLYFF DATA_SHIFT_B;
            endcase
        end            
        // the CE logic might be easier as an on/off:
        // -> 1 in RESET_PREP_A or PREP_A or COMPUTE_A_0 or DATA_SHIFT_A
        // -> 0 in PREP_B or COMPUTE_A_1 or DSP_SHIFT_A or IDLE_B (to catch the exit) or RESET
        if (state == PREP_B || state == COMPUTE_A_1 || 
            state == DSP_SHIFT_A || state == IDLE_B || state == RESET)
            beamscaler_ce[0] <= `DLYFF 0;
        else if (state == RESET_PREP_A || state == PREP_A || state == COMPUTE_A_0 || state == DATA_SHIFT_A)
            beamscaler_ce[0] <= `DLYFF 1;

        if (state == PREP_A || state == COMPUTE_B_1 ||
            state == DSP_SHIFT_B || state == IDLE_A || state == RESET)
            beamscaler_ce[1] <= `DLYFF 0;
        else if (state == PREP_B || state == COMPUTE_B_0 || state == DATA_SHIFT_B)
            beamscaler_ce[1] <= `DLYFF 1;            
        
        if (state == DATA_SHIFT_A) dsp_capture_A <= `DLYFF final_out[0][23:0];
        else if (state == DSP_SHIFT_A) dsp_capture_A <= `DLYFF final_out[0][47:24];
        
        if (state == DATA_SHIFT_B) dsp_capture_B <= `DLYFF final_out[1][23:0];
        else if (state == DSP_SHIFT_B) dsp_capture_B <= `DLYFF final_out[1][47:24];
    end        

    wire ifclk_ce;
    wire wb_clk_ce;
    
    // divide by 7 is the max we can do in 3 bits
    clk_div_ce #(.CLK_DIVIDE(6)) u_ce_gen(.clk(ifclk_i),
                                          .ce(ifclk_ce));
    flag_sync u_ce_sync(.in_clkA(ifclk_ce),.out_clkB(wb_clk_ce),
                        .clkA(ifclk_i),.clkB(wb_clk_i));                 

    generate
        genvar i;
        if (DEBUG == "TRUE") begin : DBG
            // just cheat for now
            localparam int DBG0 = 0;
            localparam int DBG1 = 2;
            wire [1:0] trig_flag;
            wire [1:0] subthresh_flag;
            flag_sync u_trig0_flag(.in_clkA(count_i[DBG0]),.out_clkB(trig_flag[0]),
                                   .clkA(ifclk_i),.clkB(wb_clk_i));
            flag_sync u_trig1_flag(.in_clkA(count_i[DBG1]),.out_clkB(trig_flag[1]),
                                   .clkA(ifclk_i),.clkB(wb_clk_i));
            flag_sync u_subt0_flag(.in_clkA(count_i[NBEAMS+DBG0]),.out_clkB(subthresh_flag[0]),
                                   .clkA(ifclk_i),.clkB(wb_clk_i));
            flag_sync u_subt1_flag(.in_clkA(count_i[NBEAMS+DBG1]),.out_clkB(subthresh_flag[1]),
                                   .clkA(ifclk_i),.clkB(wb_clk_i));
                                   
            beamscaler_ila u_ila(.clk(wb_clk_i),
                                 .probe0(state),
                                 .probe1(dsp_capture_A),
                                 .probe2(dsp_capture_B),
                                 .probe3(trig_flag),
                                 .probe4(subthresh_flag));
        end
        for (i=0;i<NUM_QSCAL;i=i+1) begin : BSC
            // QSCAL 0 gets: count_i[NBEAMS+1], count_i[1], count_i[NBEAMS], count_i[0]
            wire [3:0] count_in;
            assign count_in[0] = count_i[2*i];
            assign count_in[1] = count_i[NBEAMS+2*i];
            if (2*i+1 >= NBEAMS) begin : TAIL
                assign count_in[2] = 1'b0;
                assign count_in[3] = 1'b0;
            end else begin : FULL
                assign count_in[2] = count_i[2*i+1];
                assign count_in[3] = count_i[NBEAMS+2*i+1];
            end
            wire [48*2-1:0] dsp_out;
            beamscaler #(.CASCADE(i==0 ? "FALSE" : "TRUE"),
                         .IFCLKTYPE(IFCLKTYPE),
                         .WBCLKTYPE(WBCLKTYPE))
                u_scaler(.ifclk_i(ifclk_i),
                         .ifclk_ce_i(ifclk_ce),
                         .count_i(count_in),
                         .wb_clk_i(wb_clk_i),
                         .wb_clk_ce_i(wb_clk_ce),
                         .state_i( beamscaler_state ),
                         .state_ce_i( beamscaler_state_ce ),
                         .dsp_ce_i( beamscaler_ce ),
                         .rstp_i(beamscaler_reset),
                         .pc_i(cascade[i]),
                         .pc_o(cascade[(i+1)%NUM_QSCAL]),
                         .count_o(dsp_out));
            if (i == NUM_QSCAL-1) begin : FINAL
                assign final_out = dsp_out;
            end
        end
    endgenerate

    wire [63:0] ram_dina = { {4{1'b0}}, dsp_capture_B[12 +: 12],
                             {4{1'b0}}, dsp_capture_B[0 +: 12],
                             {4{1'b0}}, dsp_capture_A[12 +: 12],
                             {4{1'b0}}, dsp_capture_A[0 +: 12] };
    wire [7:0] ram_wea = {   {4{scaler_write[1]}},
                             {4{scaler_write[0]}} };
    wire ram_ena = scaler_write_any;
    
    // ALL WE HAVE LEFT IS THE ACTUAL RAM!!!
    // NO WE CANNOT INFER THIS, IT AIN'T SUPPORTED
    // 8 bit on write side
    // 9 bit on read side
    xpm_memory_sdpram #(.ADDR_WIDTH_A(8),
                        .ADDR_WIDTH_B(9),
                        .READ_DATA_WIDTH_B(32),
                        .WRITE_DATA_WIDTH_A(64),
                        .BYTE_WRITE_WIDTH_A(8),
                        .MEMORY_SIZE(16384))
        u_scaler_ram(.clka(wb_clk_i),
                     .dina(ram_dina),
                     .addra(scaler_addr_remap),
                     .wea(ram_wea),
                     .ena(ram_ena),
                     .rstb(wb_rst_i),
                     .addrb({scal_adr_i, !active_write_bank}),
                     .doutb(scal_dat_o),
                     .enb(scal_rd_i),
                     .regceb(1'b1));
    
    assign done_o = update_done;

    assign write_bank_o = active_write_bank;
endmodule
