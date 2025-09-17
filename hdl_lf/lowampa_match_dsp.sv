`timescale 1ns / 1ps
// basic parameterizable core DSP for FIR
// UPDATE: this core now handles loadable coefficients OPTIONALLY
// but only in a sequence load setup
//
// parameters
// ADD_PCIN = "TRUE"/"FALSE" (default)
// USE_C = "TRUE" (default)/"FALSE"
// USE_RND = "TRUE"/"FALSE" (default) -- READ NOTE BELOW
// RND_VAL = {48{1'b0}} (default)     -- READ NOTE BELOW
// USE_PATTERN = "TRUE"/"FALSE" (default) - use pattern detect
// PATTERN = {48{1'b0}} (default) -- pattern to look for
// USE_ACIN = "TRUE"/"FALSE" (default)
// USE_ACOUT = "TRUE"/"FALSE" (default)
// SUBTRACT_A = "FALSE" (default) / "TRUE"
// AREG = 0 / 1 (default) / 2
// DREG = 0 / 1 (default)
// CREG = 0 / 1 (default)
// PREADD_REG = 0 (default) / 1 (adds register after preadder)
// MULT_REG = 0 (default) / 1 (adds register after multiplier)
//
////////////////////////////////////////////
//
// USE_RND NOTES:
// DSP48s fundamentally have a 4-element ALU, however, the
// multiplier takes 2 slots for its partial products. So we only
// have 2 available slots, the W and Z inputs.
//
// fir_dsp_core allows for using any 2 of C, PCIN, or RND for
// those slots, but you cannot use all 3. Thankfully Vivado
// now enables $fatal on invalid parameters, so elaboration
// will fail if ADD_PCIN = "TRUE", USE_C = "TRUE" and
// USE_RND = "TRUE".
//
// You can use USE_RND to add a constant rather than feeding
// a constant value into the C port. Dunno if this is better
// or if they're functionally identical.
//
////////////////////////////////////////////
//
// INPUT REGISTER NOTES:
// Note that a choice between PREADD_REG/MULT_REG for adding
// delay depends on different factors. If you have internal registers
// already (AREG/DREG are both not 0) then MREG is the preferential
// first choice.
//
// A/C/DREG all control input register delays.
//
// You should probably wrap these functions in something else
// to make sure that coefficients and data are passed properly.
//
////////////////////////////////////////////
// LOADABLE_B NOTES:
// LOADABLE_B can either be HEAD, BODY, TAIL, or NONE (default)
// BODY/TAIL both use BCIN.
// Note that if you only have 1 just use HEAD.
//
///////////////////////////////////////////
// CLKTYPE allows cross-clock for coeff_dat using CUSTOM_CC_DST
///////////////////////////////////////////
module lowampa_match_dsp #(
	parameter ADD_PCIN = "FALSE"
    )(
        input clk_i,
        input rst_i,
        input [47:0] pcin_i,
        input [25:0] a_i,
        input [25:0] d_i,
        input [17:0] b_i,
        input [47:0] c_i,
        output [47:0] p_o,
        output [47:0] pcout_o
    );

    localparam ce =  1'b1;
    
    `define RESETS( port )  \
        .RSTA( port ),      \
        .RSTB( port ),      \
        .RSTC( port ),      \
        .RSTD( port ),      \
        .RSTP( port )

    // parameterize the clock enables
//    `define CLOCK_ENABLES( port )   \
//        .CEA1(DSP_AREG == 2 ? port : 1'b0),                 \
//        .CEA2(AREG != 0 ? port : 1'b0),                 \
//        .CEM(MULT_REG != 0 ? port : 1'b0),                 \
//        .CEP(PREG != 0 ? port : 1'b0),                \
//        .CEAD(PREADD_REG != 0 ? port : 1'b0)
`define CLOCK_ENABLES( port )   \
        .CEA1(1'b1),                 \
        .CEA2(1'b1),                 \
        .CEM(1'b1),                 \
        .CEP(1'b1),                \
        .CEAD(1'b1)
   
    // extend by 4 or 1. Extend by 4 b/c if we don't use Dport, gets passed to multiplier
    wire [29:0] DSP_A = { {4{a_i[25]}}, a_i };
    // if we don't use Dport tie everything high for lowest leakage
    wire [26:0]	DSP_D = { d_i[25], d_i };   
    wire [17:0] DSP_B = b_i;
    // if we're subtracting, we need to flip C
    wire [47:0] DSP_C = c_i;        
    // the reason we need a billion damn options is b/c you CANNOT hook up a cascade input
    // if you don't plan on using it.
    generate
        if (ADD_PCIN == "TRUE") begin : CSC        
		//cascade input
		//(* CUSTOM_CC_DST = CLKTYPE *)		
                DSP48E2 #( .ACASCREG(1 ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( 0 ),
                           .ALUMODEREG(1'b0),
                           .AREG(1),
                           .BREG(0),
                           .BCASCREG( 0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(1'b1),
                           .DREG(1'b1),
                           .INMODEREG(1'b0),
                           .MREG(0),
                           .OPMODEREG(1'b0),
                           .PREG(1),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
			   .RND(48'b0),
			               .USE_PATTERN_DETECT("NO_PATDET"),
			               .SEL_PATTERN("PATTERN"),
			               .PATTERN(48'b0),
			               .MASK({48{1'b1}}),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT( acout_o ),
                                    .B(DSP_B),
				    .CEB1( 1'b0 ),
				    .CEB2( 1'b0 ),
				    .BCOUT(bcout_o),
                                    .C(DSP_C),
                                    .CARRYIN(1'b0),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .PCIN(pcin_i),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .PCOUT(pcout_o),
                                    .INMODE(5'b00100),
                                    .OPMODE(9'b110010101),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( 1'b1 ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(4'b0));                
        end // block: CSC
        else begin : NCSC
		   // No cascade input
		//(* CUSTOM_CC_DST = CLKTYPE *)		
                DSP48E2 #( .ACASCREG(1 ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( 0 ),
                           .ALUMODEREG(1'b0),
                           .AREG(1),
                           .BREG(0),
                           .BCASCREG( 0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(1'b1),
                           .DREG(1'b1),
                           .INMODEREG(1'b0),
                           .MREG(0),
                           .OPMODEREG(1'b0),
                           .PREG(1),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
			   .RND(48'b0),
			               .USE_PATTERN_DETECT("NO_PATDET"),
			               .SEL_PATTERN("PATTERN"),
			               .PATTERN(48'b0),
			               .MASK({48{1'b1}}),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT( acout_o ),
                                    .B(DSP_B),
				    .CEB1( 1'b0 ),
				    .CEB2( 1'b0 ),
				    .BCOUT(bcout_o),
                                    .C(DSP_C),
                                    .CARRYIN(1'b0),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .PCOUT(pcout_o),
                                    .INMODE(5'b00100),
                                    .OPMODE(9'b110000101),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( 1'b1 ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(4'b0));                
		end // block: NCSCIN
       
    endgenerate                                
               
endmodule
