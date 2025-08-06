`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Beam scalers handle 2 beams and 2 thresholds each.
// Requires two DSPs, can only count up to 4095 max.
// Lots of silly DSP tricks involved here.
module beamscaler #(parameter CASCADE = "FALSE",    //! use the cascade input
                    parameter IFCLKTYPE = "NONE",   //! ifclk type
                    parameter WBCLKTYPE = "NONE"    //! wbclk type
                    )(
        input ifclk_i,              //! scaler clock
        input ifclk_ce_i,           //! periodic clock enable to transfer count to wbclk
        input [3:0] count_i,        //! count has occurred
        input wb_clk_i,             //! wishbone clock
        input wb_clk_ce_i,          //! ifclk_ce_i transferred to wishbone clock
        input [2:0] state_i,        //! 010 = count, 111 = compute, 001 = shift
        input [1:0] state_ce_i,     //! enable state transfer, 1 per DSP bank
        input [1:0] dsp_ce_i,       //! enable the P register in a DSP
        input rstp_i,               //! reset the P register in a DSP
        input [48*2-1:0] pc_i,      //! input cascade if any
        output [48*2-1:0] pc_o,     //! output cascade
        output [48*2-1:0] count_o   //! output of the P register
    );

    // wrapper state machine:
    //              timer complete      state_i     state_ce_i      dsp_ce_i
    // IDLE_A       1                   XX          00              01
    // PREP_B       0                   00          10              01
    // COMPUTE_A_0  0                   01          01              10
    // COMPUTE_A_1  0                   XX          00              11
    // DATA_SHIFT_A 0                   10          01              10
    // DSP_SHIFT_A  0                   XX          00              11
    // then bounce back and forth between DATA_SHIFT_A/DSP_SHIFT_A until
    // the end is hit, at which point go to IDLE_B and there's an identical chain
    // with B/A swapped 
    
    // ultra-mega-sleaze
    // Our scalers are now only 12 bits, but we double the DSP usage per.
    // So for 48 beams with 96 thresholds we need 24 DSPs. Not a big deal.

    // saturation detection
    reg [3:0] sat_seen_A = {4{1'b0}};
    reg [3:0] sat_seen_B = {4{1'b0}};
        
    reg [3:0][2:0] count_ifclk = {4*3{1'b0}};
          
    (* CUSTOM_CC_SRC = IFCLKTYPE *)
    reg [3:0][2:0] count_ifclk_hold = {4*3{1'b0}};
    
    // DSP now operates in 4 modes
    // 1. P = A:B + P - normal operation  
    // 2. P =   C | P - saturation handle 
    // 3. P = PCIN    - shift             

    // our 3 modes have:
    // 1. OPMODE = 00 010 00 11
    // 2. OPMODE = 00 011 10 10
    // 3. OPMODE = 00 001 00 00
    // if we map this to 3 bits we have
    // 010  ZMUX = 0,state[1],state[0]    YMUX=state[2],0   XMUX=state[1],!state[0]
    // 111
    // 001
    
    // when CASCADE is false, SHIFT doesn't need anything since it just clears the bottom.
    // So we can just do 1/2 b/c
    // 010 ZMUX = 010 = P
    // 111 ZMUX = 011 = C
    // 001 ZMUX = 000 = nothin'
    wire [2:0] dsp_ZMUX = (CASCADE == "TRUE") ? { 1'b0, state_i[1], state_i[0] } :
                                                { 1'b0, state_i[1], state_i[2] };
    wire [1:0] dsp_YMUX = { state_i[2], 1'b0 };
    wire [1:0] dsp_XMUX = { state_i[1], state_i[0] };   // this is WRONG but we invert in DSP
    wire [8:0] dsp_OPMODE = { 2'b00, dsp_ZMUX, dsp_YMUX, dsp_XMUX };
    localparam [8:0] dsp_OPMODEINV = { 2'b00, 3'b000, 2'b00, 2'b01 };
    wire [3:0] dsp_ALUMODE = { {2{state_i[2]}}, 2'b00 }; 


    wire [47:0] dsp_AB = { { {9{1'b0}}, count_ifclk_hold[3] },
                           { {9{1'b0}}, count_ifclk_hold[2] },
                           { {9{1'b0}}, count_ifclk_hold[1] },
                           { {9{1'b0}}, count_ifclk_hold[0] } };
    wire [47:0] A_dsp_C = { {12{sat_seen_A[3]}},
                            {12{sat_seen_A[2]}},
                            {12{sat_seen_A[1]}},
                            {12{sat_seen_A[0]}} };
    wire [47:0] B_dsp_C = { {12{sat_seen_B[3]}},
                            {12{sat_seen_B[2]}},
                            {12{sat_seen_B[1]}},
                            {12{sat_seen_B[0]}} };
    wire [3:0] A_dsp_CARRY;
    wire [3:0] B_dsp_CARRY;
    
    always @(posedge ifclk_i) begin
        if (ifclk_ce_i) count_ifclk_hold <= count_ifclk;

        if (ifclk_ce_i) begin
            count_ifclk[0] <= count_i[0];
            count_ifclk[1] <= count_i[1];
            count_ifclk[2] <= count_i[2];
            count_ifclk[3] <= count_i[3];
        end else begin
            count_ifclk[0] <= count_ifclk[0] + count_i[0];
            count_ifclk[1] <= count_ifclk[1] + count_i[1];
            count_ifclk[2] <= count_ifclk[2] + count_i[2];
            count_ifclk[3] <= count_ifclk[3] + count_i[3];
        end
    end
    always @(posedge wb_clk_i) begin    
        if ((state_ce_i[0] && state_i[2]) | rstp_i) sat_seen_A <= {4{1'b0}};
        else begin
            sat_seen_A <= A_dsp_CARRY | sat_seen_A;
        end
        if ((state_ce_i[1] && state_i[2]) | rstp_i) sat_seen_B <= {4{1'b0}};
        else begin
            sat_seen_B <= B_dsp_CARRY | sat_seen_B;
        end        
    end

    generate
        if (CASCADE == "FALSE") begin : NCSC
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            DSP48E2 #(`NO_MULT_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .AREG(1),
                      .BREG(1),
                      .CREG(1),
                      .PREG(1),
                      .OPMODEREG(1),
                      .IS_OPMODE_INVERTED( dsp_OPMODEINV ),
                      .IS_RSTA_INVERTED(1'b1),
                      .IS_RSTB_INVERTED(1'b1),
                      .ALUMODEREG(1),
                      .CARRYINREG(0),
                      .CARRYINSELREG(0))
                      u_dspA(
                        .CLK( wb_clk_i ),
                        .A( `DSP_AB_A(dsp_AB) ),
                        .B( `DSP_AB_B(dsp_AB) ),
                        .RSTA( wb_clk_ce_i ),
                        .RSTB( wb_clk_ce_i ),
                        .RSTC(1'b0),   
                        .C( A_dsp_C ),          
                        .CEA2(1'b1),.CEB2(1'b1),.CEC(1'b1),
                        .OPMODE( dsp_OPMODE ),
                        .ALUMODE( dsp_ALUMODE ),
                        .CECTRL( state_ce_i[0] ),
                        .CEALUMODE( state_ce_i[0] ),
                        .CEP( dsp_ce_i[0] ),
                        .CARRYOUT( A_dsp_CARRY ),
                        .RSTCTRL( rstp_i ),
                        .RSTP( rstp_i ),
                        .P( count_o[0 +: 48] ),
                        .PCOUT( pc_o[0 +: 48] )
                      );
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            DSP48E2 #(`NO_MULT_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .AREG(1),
                      .BREG(1),
                      .CREG(1),
                      .PREG(1),
                      .OPMODEREG(1),
                      .IS_OPMODE_INVERTED( dsp_OPMODEINV ),
                      .IS_RSTA_INVERTED(1'b1),
                      .IS_RSTB_INVERTED(1'b1),
                      .ALUMODEREG(1),
                      .CARRYINREG(0),
                      .CARRYINSELREG(0))
                      u_dspB(
                        .CLK( wb_clk_i ),
                        .A( `DSP_AB_A(dsp_AB) ),
                        .B( `DSP_AB_B(dsp_AB) ),
                        .RSTA( wb_clk_ce_i ),
                        .RSTB( wb_clk_ce_i ),
                        .C( B_dsp_C ),       
                        .RSTC(1'b0),   
                        .CEA2(1'b1),.CEB2(1'b1),.CEC(1'b1),
                        .OPMODE( dsp_OPMODE ),
                        .ALUMODE( dsp_ALUMODE ),
                        .CECTRL( state_ce_i[1] ),
                        .CEALUMODE( state_ce_i[1] ),
                        .CEP( dsp_ce_i[1] ),
                        .CARRYOUT( B_dsp_CARRY ),
                        .RSTCTRL( rstp_i ),
                        .RSTP( rstp_i ),
                        .P( count_o[48 +: 48] ),
                        .PCOUT( pc_o[48 +: 48] ) 
                      );
        end else begin : CSC
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            DSP48E2 #(`NO_MULT_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .AREG(1),
                      .BREG(1),
                      .CREG(1),
                      .PREG(1),
                      .OPMODEREG(1),
                      .IS_OPMODE_INVERTED( dsp_OPMODEINV ),
                      .IS_RSTA_INVERTED(1'b1),
                      .IS_RSTB_INVERTED(1'b1),
                      .ALUMODEREG(1),
                      .CARRYINREG(0),
                      .CARRYINSELREG(0))
                      u_dspA(
                        .CLK( wb_clk_i ),
                        .A( `DSP_AB_A(dsp_AB) ),
                        .B( `DSP_AB_B(dsp_AB) ),
                        .RSTA( wb_clk_ce_i ),
                        .RSTB( wb_clk_ce_i ),
                        .RSTC(1'b0),   
                        .C( A_dsp_C ),          
                        .CEA2(1'b1),.CEB2(1'b1),.CEC(1'b1),
                        .OPMODE( dsp_OPMODE ),
                        .ALUMODE( dsp_ALUMODE ),
                        .CECTRL( state_ce_i[0] ),
                        .CEALUMODE( state_ce_i[0] ),
                        .CEP( dsp_ce_i[0] ),
                        .CARRYOUT( A_dsp_CARRY ),
                        .RSTCTRL( rstp_i ),
                        .RSTP( rstp_i ),
                        .P( count_o[0 +: 48] ),
                        .PCIN( pc_i[0 +: 48] ),
                        .PCOUT( pc_o[0 +: 48] )
                      );
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            DSP48E2 #(`NO_MULT_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .AREG(1),
                      .BREG(1),
                      .CREG(1),
                      .PREG(1),
                      .OPMODEREG(1),
                      .IS_OPMODE_INVERTED( dsp_OPMODEINV ),
                      .IS_RSTA_INVERTED(1'b1),
                      .IS_RSTB_INVERTED(1'b1),
                      .ALUMODEREG(1),
                      .CARRYINREG(0),
                      .CARRYINSELREG(0))
                      u_dspB(
                        .CLK( wb_clk_i ),
                        .A( `DSP_AB_A(dsp_AB) ),
                        .B( `DSP_AB_B(dsp_AB) ),
                        .RSTA( wb_clk_ce_i ),
                        .RSTB( wb_clk_ce_i ),
                        .RSTC(1'b0),   
                        .C( B_dsp_C ),          
                        .CEA2(1'b1),.CEB2(1'b1),.CEC(1'b1),
                        .OPMODE( dsp_OPMODE ),
                        .ALUMODE( dsp_ALUMODE ),
                        .CECTRL( state_ce_i[1] ),
                        .CEALUMODE( state_ce_i[1] ),
                        .CEP( dsp_ce_i[1] ),
                        .CARRYOUT( B_dsp_CARRY ),
                        .RSTCTRL( rstp_i ),
                        .RSTP( rstp_i ),
                        .P( count_o[48 +: 48] ),
                        .PCIN( pc_i[48 +: 48] ),
                        .PCOUT( pc_o[48 +: 48] ) 
                      );
        end                    
    endgenerate                                                  
endmodule
