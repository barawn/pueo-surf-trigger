`timescale 1ns / 1ps
`include "dsp_macros.vh"
// DO NOT USE this with a delay under 5.
module preset_timer #(parameter WIDTH=32,
                      parameter [WIDTH-1:0] DEFAULT_COUNT = 100000000,
                      localparam [WIDTH-1:0] BASE_DELAY = DEFAULT_COUNT - 5)(
        input clk_i,
        input rst_i,
        input ce_i,
        input [WIDTH-1:0] max_count_i,
        input max_count_wr_i,
        output count_reached_o
    );
    
    reg reset = 1;
    wire instruction_sel;
    // aaugh
    wire [47:0] dsp_P;    
    wire carryout;
    reg count_reached = 0;    
    wire [47:0] dsp_CIN = { {(48-WIDTH){max_count_i[WIDTH-1]}}, max_count_i };    
    wire [47:0] dsp_CONCAT = { {(48-WIDTH){1'b0}}, BASE_DELAY };    
    assign instruction_sel = (reset || dsp_P[47]);
    // 0 = C + CONCAT
    // 1 = P - CARRYIN
    // i dunno how you *do* this but HEY
    
    // OK this is THE STUPIDEST
    always @(posedge clk_i) begin
        if (rst_i) reset <= 1;
        else reset <= 0;
        
        count_reached <= !carryout && dsp_P[47];
    end
    
    preset_timer_dsp dsp(.CLK(clk_i),
                    .SCLRP(reset),
                    .SEL(instruction_sel),
                    .CEC5(max_count_wr_i),
                    .P(dsp_P),
                    .C(dsp_CIN),
                    .CARRYIN(1'b1),
                    .CARRYOUT(carryout),
                    .CONCAT(dsp_CONCAT));    
    assign count_reached_o = count_reached;    
//    // we use round for the reset value initially and then it can be
//    // updated with max_count
//    localparam [47:0] ROUND_VAL = {{(48-WIDTH){1'b0}},DEFAULT_COUNT};
        
//    reg use_custom = 0;
//    reg reset = 1;
//    reg was_reset = 0;
//    reg count_reached = 0;
//    wire [3:0] carryout;
//    wire carry = carryout[3];
//    always @(posedge clk_i) begin
//        if (rst_i) reset <= 1;
//        else reset <= 0;

//        // reset does not depend on cep so
//        if (reset) was_reset <= 1;
//        else if (ce_i) was_reset <= 0;

//        count_reached <= carry && !was_reset && ce_i;        
//        if (rst_i)
//            use_custom <= 0;
//        else if (max_count_wr_i)
//            use_custom <= 1;
//    end
    
//    // this will technically start off subtracting 1, hitting carry, and resetting
//    wire [8:0] dsp_OPMODE = { carry, use_custom && ~carry, 1'b0, carry, 1'b0, {4{1'b0}} };
//    localparam [8:0] dsp_OPMODE_INVERTED = 9'b100000000;
//    wire [3:0] dsp_ALUMODE = { 2'b00, {2{carry}} };
    
//    DSP48E2 #(`NO_MULT_ATTRS,
//              `A_UNUSED_ATTRS,
//              `B_UNUSED_ATTRS,
//              `DE2_UNUSED_ATTRS,
//              .IS_OPMODE_INVERTED(dsp_OPMODE_INVERTED),
//              .IS_CARRYIN_INVERTED(1'b1),
//              .CREG(1),.PREG(1),
//              .OPMODEREG(0),
//              .ALUMODEREG(0),
//              .CARRYINREG(0))
//              u_dsp(.CLK(clk_i),
//                    .RSTP(reset),
//                    .OPMODE(dsp_OPMODE),
//                    .ALUMODE(dsp_ALUMODE),
//                    .CARRYIN(carry),
//                    .C(max_count_i),
//                    .CEC(max_count_wr_i),
//                    .CEP(ce_i),
//                    .CARRYOUT(carryout));    

//    assign count_reached_o = count_reached;    
endmodule
