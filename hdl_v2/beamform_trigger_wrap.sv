`timescale 1ns / 1ps
// include trigger and ifclk stretch
module beamform_trigger_wrap #(parameter CLKTYPE = "NONE",
                               parameter NBEAMS = 2,
                               parameter WBCLKTYPE = "NONE",
                               localparam AGC_BITS = 5,
                               localparam NSAMPS = 8,
                               localparam NCHAN = 8)(
        input tclk,
        input [NCHAN-1:0][NSAMPS*AGC_BITS-1:0] dat_i,
        
        input [17:0] thresh_i,
        input [NBEAMS-1:0] thresh_ce_i,
        input update_i,
        
        input aclk,
        input aclk_phase_i,
        input ifclk,
        output [NBEAMS-1:0] trigger_o        
    );

    // output trigger signals
    wire [NBEAMS-1:0] trigger_signal_bit_o;    
    
    beamform_trigger #(.NBEAMS(NBEAMS),
                       .WBCLKTYPE(WBCLKTYPE),
                       .CLKTYPE(CLKTYPE)) 
        u_trigger(
            .clk_i(tclk),
            .data_i(dat_i),

            .thresh_i(thresh_i),
            .thresh_ce_i(thresh_ce_i),
            .update_i(update_i),        
            
            .trigger_o(trigger_signal_bit_o));

    // OK - the trigger signals come out in aclk (well tclk but whatever)
    // we're going to stretch them so they can be handled in ifclk because
    // aclk is too fast. This also lets us redo the trigger processor,
    // and also simplify the counting.
    // We first want to stretch them in aclk, then we'll pass them over
    // with a full multicycle path to ifclk.
    //
    // aclk phase 0 : aclk_phase_buf == 2'b00, aclk_phase_i = 1
    // aclk phase 1 : aclk_phase_buf == 2'b01, aclk_phase_i = 0
    // aclk phase 2 : aclk_phase_buf == 2'b10, aclk_phase_i = 0     <-- next rising edge of aclk
    //                                                                  is rising edge of ifclk 
    // stretching in aclk is just: set if !aclk_phase_buf[1] and capture in 
    // aclk_phase_buf[1]. So this becomes:
    // trig comes in on aclk phase 1
    // clk  trig    stretch     aclk_phase
    // 0    0       0           0
    // 1    1       0           1
    // 2    0       1           2
    // 3    0       0           0
    // trig comes in on aclk phase 0
    // clk  trig    stretch     aclk_phase
    // 0    1       0           0
    // 1    0       1           1
    // 2    0       1           2
    // 3    0       0           0
    // trig comes in on aclk phase 2
    // clk  trig    stretch     aclk_phase
    // 0    0       0           0
    // 1    0       0           1
    // 2    1       0           2
    // 3    0       1           0
    // 4    0       1           1
    // 5    0       1           2
    // 6    0       0           0
    // this means we can then reregister stretch conditioned on aclk_phase 2 to get
    // clk  trig    stretch     aclk_phase  trigger_to_ifclk
    // 0    0       0           0           0
    // 1    1       0           1           0
    // 2    0       1           2           0
    // 3    0       0           0           1
    // 4    0       0           1           1
    // 5    0       0           2           1
    // 6    0       0           0           0
    // trigger_to_ifclk goes to ifclk with a full 8 ns multicycle path.
    reg [NBEAMS-1:0] trigger_aclk = {NBEAMS{1'b0}};
    reg [NBEAMS-1:0] trigger_stretch_aclk = {NBEAMS{1'b0}};
    (* CUSTOM_MC_SRC_TAG = "TRIG_TRANSFER", CUSTOM_MC_MIN = "0", CUSTOM_MC_MAX = "3.0" *)
    reg [NBEAMS-1:0] trigger_to_ifclk = {NBEAMS{1'b0}};
    (* CUSTOM_MC_DST_TAG = "TRIG_TRANSFER" *)
    reg [NBEAMS-1:0] trigger_in_ifclk = {NBEAMS{1'b0}};
    reg [1:0] aclk_phase_buf = {2{1'b0}};
    integer ti;
    always @(posedge aclk) begin
        aclk_phase_buf <= { aclk_phase_buf[0], aclk_phase_i };
        trigger_aclk <= trigger_signal_bit_o;

        for (ti=0;ti<NBEAMS;ti=ti+1) begin
            if (aclk_phase_buf[2])
                trigger_stretch_aclk[ti] <= trigger_aclk[ti];
            else if (trigger_aclk[ti])
                trigger_stretch_aclk[ti] <= 1; 
        end        

        if (aclk_phase_buf[2])
            trigger_to_ifclk <= trigger_stretch_aclk;
    end
    // ahhh we're now back in slow land
    always @(posedge ifclk) begin
        trigger_in_ifclk <= trigger_to_ifclk;
    end
    
    assign trigger_o = trigger_in_ifclk;
    
endmodule
