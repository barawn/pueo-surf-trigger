`timescale 1ns / 1ps
`include "dsp_macros.vh"
module dual_pueo_threshold_v2 #(parameter CASCADE = "TRUE")(
        input            clk_i,
        input [18*2-1:0] thresh_i,          //! ONLY the first one uses this!
        input [1:0]      thresh_wr_i,       //! EVERYONE uses this
        input [1:0]      thresh_update_i,   //! EVERYONE uses this
        input [18*2-1:0] envelope_i,
        output [3:0]     trigger_o,
        input [47:0]     ab_casc_i,
        output [47:0]    ab_casc_o
    );

    wire dspA_CEB1 = thresh_wr_i[0];
    wire dspA_CEA1 = thresh_wr_i[1];
    wire dspA_CEB2 = thresh_update_i[0];
    wire dspA_CEA2 = thresh_update_i[1];

    reg [1:0] dspB_update = {2{1'b0}};
    
    wire dspB_CEB1 = thresh_wr_i[0];
    wire dspB_CEA1 = thresh_wr_i[1];
    wire dspB_CEB2 = dspB_update[0];
    wire dspB_CEA2 = dspB_update[1];
    
    wire [47:0] dspA_AB = { {6{1'b0}}, thresh_i[18 +: 18],
                            {6{1'b0}}, thresh_i[0 +: 18] };
    wire [47:0] dspA_C = { {6{1'b0}}, envelope_i[18 +: 18],
                           {6{1'b0}}, envelope_i[0 +: 18] };                            

    // we need to Be Clever to avoid carry issues.
    // The FIRST DSP calculates the main trigger. The NEXT
    // DSP FURTHER subtracts off MORE to get the subthreshold
    // scaler.
    wire [47:0] ab_cascade;
    wire [47:0] p_cascade;
    
    wire [3:0] dspA_carryout;
    reg [1:0] main_trigger = {2{1'b0}};
    wire [3:0] dspB_carryout;
    reg [1:0] subthresh_trigger = {2{1'b0}};
    
    wire [47:0] dspB_pout;
    
    always @(posedge clk_i) begin
        dspB_update <= thresh_update_i;
        main_trigger <= {!dspA_carryout[`DUAL_DSP_CARRY1], !dspA_carryout[`DUAL_DSP_CARRY0]};
        subthresh_trigger <= {!dspB_carryout[`DUAL_DSP_CARRY1], !dspB_carryout[`DUAL_DSP_CARRY0]} | main_trigger;
    end
    
    generate
        if (CASCADE == "FALSE") begin : NCSC
            DSP48E2 #(.USE_SIMD("TWO24"),
                      `NO_MULT_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      .RND(48'h000001000001),
                      .ACASCREG(1),.BCASCREG(1),
                      .AREG(2),.BREG(2),.CREG(1),.PREG(1))
                      u_dspA(
                        .CLK(clk_i),
                        .CEA1(dspA_CEA1),
                        .CEA2(dspA_CEA2),
                        .CEB1(dspA_CEB1),
                        .CEB2(dspA_CEB2),
                        .CEC(1'b1),
                        .CEP(1'b1),
                        .A( `DSP_AB_A( dspA_AB ) ),
                        .B( `DSP_AB_B( dspA_AB ) ),
                        .C( dspA_C ),
                        `D_UNUSED_PORTS,
                        .ACOUT( ab_cascade[18 +: 30] ),
                        .BCOUT( ab_cascade[0 +: 18] ),
                        .PCOUT( p_cascade ),
                        .CARRYOUT( dspA_carryout ),
                        .RSTA(1'b0),.RSTB(1'b0),.RSTC(1'b0),.RSTP(1'b0),
                        .OPMODE( { 2'b10, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB } ),
                        .ALUMODE( `ALUMODE_XYCIN_MINUS_Z_MINUS_1 ),
                        .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                        .CARRYIN(1'b0)
                      );
        end else begin : CSC
            DSP48E2 #(.USE_SIMD("TWO24"),
                      `NO_MULT_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .RND(48'h000001000001),
                      .ACASCREG(1),.BCASCREG(1),
                      .A_INPUT("CASCADE"),
                      .B_INPUT("CASCADE"),
                      .AREG(2),.BREG(2),.CREG(1),.PREG(1))
                      u_dspA(
                        .CLK(clk_i),
                        .CEA1(dspA_CEA1),
                        .CEA2(dspA_CEA2),
                        .CEB1(dspA_CEB1),
                        .CEB2(dspA_CEB2),
                        .C( dspA_C ),
                        `D_UNUSED_PORTS,
                        .CEP(1'b1),
                        .ACIN( ab_casc_i[ 18 +: 30 ] ),
                        .BCIN( ab_casc_i[ 0 +: 18 ] ),
                        .ACOUT( ab_cascade[ 18 +: 30 ] ),
                        .BCOUT( ab_cascade[ 0 +: 18 ] ),
                        .PCOUT( p_cascade ),
                        .CARRYOUT( dspA_carryout ),                        
                        .RSTA(1'b0),.RSTB(1'b0),.RSTC(1'b0),.RSTP(1'b0),
                        .OPMODE( { 2'b10, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB } ),
                        .ALUMODE( `ALUMODE_XYCIN_MINUS_Z_MINUS_1 ),
                        .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                        .CARRYIN(1'b0)
                      );        
        end
    endgenerate
    // Once you get to the second threshold, now you're
    // subtracting the threshold from PCIN.
    DSP48E2 #(.USE_SIMD("TWO24"),
              `NO_MULT_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `DE2_UNUSED_ATTRS,
              `C_UNUSED_ATTRS,
              .ACASCREG(1),.BCASCREG(1),
              .A_INPUT("CASCADE"),
              .B_INPUT("CASCADE"),
              .AREG(2),.BREG(2),.PREG(1))
              u_dspB(
                .CLK(clk_i),
                .CEA1(dspB_CEA1),
                .CEA2(dspB_CEA2),
                .CEB1(dspB_CEB1),
                .CEB2(dspB_CEB2),
                `C_UNUSED_PORTS,
                `D_UNUSED_PORTS,
                .CEP(1'b1),
                .ACIN( ab_cascade[ 18 +: 30 ] ),
                .BCIN( ab_cascade[ 0 +: 18 ] ),                
                .ACOUT( ab_casc_o[ 18 +: 30 ] ),
                .BCOUT( ab_casc_o[ 0 +: 18 ] ),
                .PCIN( p_cascade ),
                .P(dspB_pout),
                .CARRYOUT( dspB_carryout ),
                .RSTA(1'b0),.RSTB(1'b0),.RSTP(1'b0),
                .OPMODE( { 2'b00, `Z_OPMODE_PCIN, `Y_OPMODE_0, `X_OPMODE_AB } ),
                .ALUMODE( `ALUMODE_Z_MINUS_XYCIN ),
                .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                .CARRYIN(1'b0)
              );        

    assign trigger_o[0] = main_trigger[0];
    assign trigger_o[1] = subthresh_trigger[0];
    assign trigger_o[2] = main_trigger[1];
    assign trigger_o[3] = subthresh_trigger[1];
    
endmodule
