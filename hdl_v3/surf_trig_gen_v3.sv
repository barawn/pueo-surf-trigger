`timescale 1ns / 1ps
// THIS HAS TO BE MODIFIED FOR ANYTHING MORE THAN 48 BEAMS
// NO METADATA YET FRIGGIN DEAL WITH IT
`include "interfaces.vh"
`include "dsp_macros.vh"
// NOTE NOTE NOTE - THIS HAS TO BE RUNNING OUTSIDE OF TCLK
// TO MAINTAIN PHASE
//
//
// TOTAL LATENCY:
// aclk:
// 0 trigger high on input
// 1 trigger high in C
// 2 trigger high at register
// 3 trigger high at trigger_registered
// 4 trigger_high at trigger_stretch
// 5-7: trigger high at trigger_ifclk
// + 37 clock latency
// = 42-44 ACLK clocks = 14-15 addresses

// TRIG_CLOCKDOMAIN allows this to handle both ifclk
// and aclk inputs depending on whether the stretch happens
// before or after.
//
// The v3 code adds metadata generation.
// USE_V3 is passed to the metadata generation module.
module surf_trig_gen_v3 #(parameter NBEAMS=48,
                          parameter USE_V3 = "FALSE",
                          parameter ACLKTYPE = "NONE",
                          parameter IFCLKTYPE = "NONE",
                          parameter DEBUG = "TRUE",
                          parameter TRIG_CLOCKDOMAIN = "ACLK")(
        input aclk,
        // aclk phase = 1 indicates first phase of 3-clock cycle
        input aclk_phase_i,
        input [NBEAMS-1:0] trig_i,
        // mask is written stupidly: 30 bits in one register
        // and 18 bits in the other because we're using the A/B registers
        // in a 48-bit pair.
        input [47:0] mask_i,
        input [1:0] mask_wr_i,
        input [11:0] offset_i,
        input mask_update_i,
        input gen_rst_i,
        input ifclk,
        input runrst_i,
        input runstop_i,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( trig_ , 32 )        
    );

    // NO FREAKING STUFF IN ACLK ANYMORE: FIRST THING WE'RE DOING IS STRETCHING AND TRANSFERRING
    // TO IFCLK
    wire [NBEAMS-1:0] trigger_in_ifclk;
    generate
        if (TRIG_CLOCKDOMAIN == "ACLK") begin : STR
            trig_cc_stretch #(.NBEAMS(NBEAMS))
                u_stretch(.aclk(aclk),
                          .aclk_phase_i(aclk_phase_i),
                          .trig_i(trig_i),
                          .ifclk(ifclk),
                          .trig_o(trigger_in_ifclk));
        end else begin : DIR
            assign trigger_in_ifclk = trig_i;
        end
    endgenerate        

    // can send 1 trigger per 8 clocks
    localparam TRIG_CLOCK_RATE = 8;
    // imagine a 4 clock cycle
    // clk  trigger     trigger_registered      trig_holdoff    trig_holdoff_complete   shreg
    // 0    0           0                       0               0                       000
    // 1    1           0                       0               0                       000
    // 2    X           1                       1               0                       000
    // 3    X           0                       1               0                       001
    // 4    X           0                       1               1                       010
    // 5    1           0                       0               0                       100
    // 6    X           1                       1               0                       000
    // this would need a shreg address of 0
    // so we have to subtract 4
    localparam [4:0] HOLDOFF_ADDR = TRIG_CLOCK_RATE-4;
    
    // first step is to do the reductive-or
    // this is best done in a DSP.
    wire [47:0] dsp_mask_in = (NBEAMS < 48) ? { {(NBEAMS-48){1'b0}}, mask_i } : mask_i;
    wire [47:0] dsp_trig_in = (NBEAMS < 48) ? { {(NBEAMS-48){1'b0}}, trig_i } : trig_i;
    
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg [1:0] trig_gen_rst = {2{1'b0}};
    // output of DSP
    wire not_trigger;
    
    // reregistered output
    reg trigger = 0;
    // flop registering the patterndetect output - generates a flag due to holdoff
    reg trigger_registered = 0;
    // trigger_registered through the shreg
    wire trig_holdoff_dly;
    // registered shreg output
    reg trig_holdoff_complete = 0;
    // prevent new triggers
    reg trig_holdoff = 0;
    
    SRLC32E u_holdoff_dly(.D(trigger_registered),
                          .A(HOLDOFF_ADDR),
                          .CE(1'b1),
                          .CLK(ifclk),
                          .Q(trig_holdoff_dly));

    // same behavior as the TURF and as run_dbg
    (* CUSTOM_MC_DST_TAG = "RUNRST RUNSTOP" *)
    reg trig_running = 0;
    // address to capture
    reg [11:0] current_address = {12{1'b0}};
    // address offset
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    reg [11:0] offset_in_ifclk = {12{1'b0}};
    
    
    // captured address    
    reg [11:0] trig_address = {12{1'b0}};
    // write into the FIFO (just reregistered trigger_ifclk)
    reg trig_write = 0;
            
    // HERE'S THE TRIGGER WOOOOO
    wire [47:0] dsp_C = dsp_trig_in;
    wire [47:0] dsp_AB = ~dsp_mask_in;
    // In the V3, we actually use the masked output, so we need it.
    wire [47:0] triggered_beams;
    // Need to reregister them since trigger is registered.
    reg [47:0] triggered_beams_rereg = {48{1'b0}};
    
    // WOOT we're actually using the logic-y stuff
    //              opmode3:2       alumode3:0
    // x and z      00              1100
    // x and not z  00              1101
    // not x and z  10              1111
    // we want x and z, since A:B is X and C is Z
    // we could use the pattern detector only but we don't get double registers for free then.
    // no P reg because the pattern stuff is confusing.
    localparam [47:0] PATTERN = {48{1'b0}};
    localparam [47:0] MASK = {48{1'b0}};

    wire [8:0] dsp_OPMODE = { 2'b00, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB };
    wire [3:0] dsp_ALUMODE = 4'b1100;                        
    wire [4:0] dsp_INMODE = {5{1'b0}};
    
    (* CUSTOM_CC_DST = IFCLKTYPE *)
    DSP48E2 #(`CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              `DE2_UNUSED_ATTRS,
              .ACASCREG(2),
              .AREG(2),
              .BCASCREG(2),
              .BREG(2),
              .CREG(1),
              .PREG(0),
              .PATTERN(PATTERN),
              .MASK(MASK),
              .SEL_MASK("MASK"),
              .SEL_PATTERN("PATTERN"),
              .USE_PATTERN_DETECT("PATDET"))
        u_trig_dsp(.CLK(ifclk),
                   .A( `DSP_AB_A(dsp_AB)),
                   .B( `DSP_AB_B(dsp_AB)),
                   .C( dsp_C ),
                   .CEA1( mask_wr_i[1] ),
                   .CEB1( mask_wr_i[0] ),
                   .CEA2( mask_update_i ),
                   .CEB2( mask_update_i ),
                   .OPMODE(dsp_OPMODE),
                   .ALUMODE(dsp_ALUMODE),
                   .INMODE(dsp_INMODE),
                   .CEC( 1'b1 ),
                   .RSTC(1'b0),
                   .RSTA(1'b0),
                   .RSTB(1'b0),
                   `D_UNUSED_PORTS,
                   .P(triggered_beams),
                   .PATTERNDETECT(not_trigger));

    // and then in V3, trigger gets passed to the metadata generation,
    // and the *output* is used to pick up trigger_registered.
    // If the V3 trigger is not used, this ends up just being a straight passthrough.

    wire meta_trigger_out;
    wire [7:0] meta_out;
    // need to reregister meta out to align with trigger_registered
    reg [7:0] meta_out_rereg = {8{1'b0}};
    // and then this is the holding register, just like trig_address
    reg [7:0] trig_meta = {8{1'b0}};

    beam_meta_builder #(.USE_V3(USE_V3),
                        .FULL(NBEAMS == 2 ? "FALSE" : "TRUE"))
        u_meta(.clk_i(ifclk),
               .beam_i(triggered_beams_rereg),
               .trig_i(trigger),
               .meta_o(meta_out),
               .trig_o(meta_trigger_out));       
                        
    always @(posedge ifclk) begin
        if (runrst_i) offset_in_ifclk <= offset_i;
        // now time aligned with trigger
        triggered_beams_rereg <= triggered_beams;
        // now time aligned with trigger_registered
        meta_out_rereg <= meta_out;
        // and captured alongside trig_address
        if (trigger_registered) trig_meta <= meta_out_rereg;

        trig_gen_rst <= { trig_gen_rst[0], gen_rst_i };

        if (trig_gen_rst[1]) trigger <= 1'b0;
        else trigger <= !not_trigger;

        // EVERYTHING BELOW HERE IS LIKE THE V2 MODULE,
        // EXCEPT INSTEAD OF USING TRIGGER IT USES meta_trigger_out
        trigger_registered <= meta_trigger_out && !trig_holdoff;

        if (trig_holdoff_complete) trig_holdoff <= 0;
        else if (meta_trigger_out) trig_holdoff <= 1;        

        trig_holdoff_complete <= trig_holdoff_dly;
        
        if (runrst_i) trig_running <= 1;
        else if (runstop_i) trig_running <= 0;
        
        if (!trig_running) current_address <= 12'd1;
        else current_address <= current_address + 1;

        if (trigger_registered) trig_address <= current_address + offset_in_ifclk;
        
        trig_write <= trigger_registered;
    end
    
    // now just buffer it and send it out
    // Metadata is currently the bottom 8 bits of the second word.
    trig_gen_fifo u_fifo(.clk(ifclk),
                         .srst(trig_gen_rst[1]),
                         .wr_en(trig_write),
                         .din( { 2'b10, trig_address, 2'b00,
                                 8'h00, trig_meta } ),
                         .rd_en(trig_tvalid && trig_tready),
                         .valid(trig_tvalid),
                         .dout(trig_tdata));        

    generate
        if (DEBUG == "TRUE") begin : ILA
            (* CUSTOM_CC_DST = IFCLKTYPE *)
            reg [47:0] mask_rereg = {48{1'b0}};
            always @(posedge ifclk) begin : RR
                mask_rereg <= mask_i;
            end                
            triggen_ila u_ila(.clk(ifclk),
                              .probe0(trigger_in_ifclk),
                              .probe1(trig_tdata),
                              .probe2(trig_tready),
                              .probe3(trig_tvalid),
                              .probe4(trig_write),
                              .probe5(current_address),
                              .probe6(trig_running));
        end
    endgenerate
endmodule
