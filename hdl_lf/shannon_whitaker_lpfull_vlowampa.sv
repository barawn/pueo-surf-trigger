`timescale 1ns / 1ps
// Second version of a Shannon-Whitaker LP filter.
//
// This version ensures that all DSPs have at least a preadd or multiplier
// register in their path, which should guarantee timing even when the
// FPGA becomes extremely full.
module shannon_whitaker_lpfull_vlowampa #(parameter NBITS=12,
                                    parameter NSAMPS=4,
                                    parameter OUTQ_INT=12,
                                    parameter OUTQ_FRAC=0)(
        input clk_i,
        input [NBITS*NSAMPS-1:0] in_i,
        output [(OUTQ_INT+OUTQ_FRAC)*2*NSAMPS-1:0] out_o,
        output reg out_valid = 0
    );
    
    // coefficient definitions
    // NOTE: these are in Q3.15 format, so divide by 32768.
    //       In documentation this is described as Q0.15 but expanding to Q3.15 is automatic in definition.
    // z^-15 and z^-17
    localparam [17:0] b_coeff15 = 10342;
    // z^-11/z^-21 and z^-13/z^-19
    localparam [17:0] b_coeff11_13 = 1672; // 13 is -1672*2+128
    // z^-9 and z^-23
    localparam [17:0] b_coeff9 = -949;
    // z^-5/z^-27 and z^-7/z^-25
    localparam [17:0] b_coeff5_7 = 263; // 5 is -2*263
    // z^-1/z^-31 and z^-3/z^-29
    localparam [17:0] b_coeff1_3 = -23; // 3 is 128-23

    // Coefficients are Q3.15 (18 bits)
    // Inputs are Q17.9 (26 bits).
    // -- Q17.9 allows a *ton* of pre-adds of a 12-bit number
    //    before insertion.
    // Preadder expands to 27 bits (Q18.9)
    // Results in Q21.24, which ends up as Q24.24
    localparam MULT_INT = 17;
    localparam MULT_FRAC = 9;
    localparam ADD_INT = 24;
    localparam ADD_FRAC = 24;
    
    // for ease of use
    wire [NBITS-1:0] xin[2*NSAMPS-1:0];
    reg  [NBITS-1:0] samp_extend[NSAMPS-1:0];
    generate
        genvar ii,jj;
        for (ii=0;ii<NSAMPS;ii=ii+1) begin : S
            for (jj=0;jj<NBITS;jj=jj+1) begin : B
                assign xin[NSAMPS+ii][jj] = in_i[NBITS*ii + jj];
                assign xin[ii][jj] = samp_extend[ii][jj];
            end
        end
    endgenerate    

    // Convert between fixed point representations (this only works to EXPAND, not COMPRESS)
    // n.b. I should convert this into a function: the macro version apparently causes problems when passed with parameters.
    // Who knows, Xilinx weirdness.
    `define QCONV( inval , SRC_QINT, SRC_QFRAC, DST_QINT, DST_QFRAC )   \
        ( { {( DST_QINT - SRC_QINT ) { inval[ (SRC_QINT+SRC_QFRAC) - 1 ] }}, inval, { ( DST_QFRAC - SRC_QFRAC ) {1'b0} } } )


    // We generate 2 delayed inputs.
    wire [NBITS-1:0] xin_store[2*NSAMPS-1:0];      // these are at z^-8
    wire [NBITS-1:0] xin_delay[2*NSAMPS-1:0];      // these are at z^-32        
    // actual outputs
    wire [47:0] sample_out[NSAMPS-1:0];
    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : DLY
            // Generate the delays.
            reg [NBITS-1:0] samp_store = {NBITS{1'b0}};
            reg [NBITS-1:0] samp_store2 = {NBITS{1'b0}};
            reg [NBITS-1:0] samp_delay = {NBITS{1'b0}};
            reg [NBITS-1:0] samp_delay2 = {NBITS{1'b0}};
            wire [NBITS-1:0] samp_srldelay;
            wire [NBITS-1:0] samp_srldelay2;
            // we want z^-32: we get z^-4 from store
            // z^-12 from 3 more FF
            // we need z^-16 again, so that's A=3
            srlvec #(.NBITS(NBITS)) u_delay(.clk(clk_i),.ce(1'b1),.a(3),.din(samp_store2),.dout(samp_srldelay));
            always @(posedge clk_i) begin : DLYFF
                samp_extend[i] <= in_i[NBITS*i+11:NBITS*i];
                samp_store <= samp_extend[i];
                samp_store2 <= samp_store;
                samp_delay <= samp_srldelay;
                samp_delay2 <= samp_delay;
            end
            assign xin_store[NSAMPS+i] = samp_store;
            assign xin_store[i] = samp_store2;
            assign xin_delay[NSAMPS+i] = samp_delay;
            assign xin_delay[i] = samp_delay2;
            // Now we generate the FIR loops.
            // There are 3 overall structures: 0-2, 3-4, and 5-7.
            // However, 3 and 4 are identical except for i11/13.
            if (i<5) begin : STRUCT0
                // Structure 0 cascades.
                wire [47:0] i11_13_to_i5_7;
                wire [47:0] i5_7_to_i1_3;
                wire [47:0] i1_3_to_i15;
                wire [47:0] i15_to_i9;
                wire [29:0] i15_to_i9_acin;
                
                ///////////////////////////////////
                //             TAP 11/13         //
                ///////////////////////////////////
                
                if (i < 3) begin : STRUCT0A
                    // compute A13/A11 first.
                    reg [NBITS:0] A13 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay;
                    reg [NBITS:0] A13_delay2;
                    reg [NBITS:0] A13_delay3;
                    // generate 2*A13
                    wire [NBITS+1:0] A13x2 = { A13, 1'b0 };
                    reg [NBITS:0] A11 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A11_delay;
                    reg [NBITS:0] A11_delay2;
                    reg [NBITS:0] A11_delay3;
                    always @(posedge clk_i) begin : PREADD_11_13
                        // sign extend and add
                        A13_delay <= { xin[i+3][NBITS-1], xin[i+3] } +
                               { xin_store[i+5][NBITS-1], xin_store[i+5] };
                        A13_delay2 <= A13_delay;
                        A13_delay3 <= A13_delay2;
                        A13 <= A13_delay3;
                        // sign extend and add
                      A11_delay2 <= A11_delay;
                      A11_delay3 <= A11_delay2;
                      A11 <= A11_delay3;
                      A11_delay <= { xin_store[i+3][NBITS-1], xin_store[i+3] } +
                      { xin[i+5][NBITS-1], xin[i+5] };
                    end
                    // AD/C/PREG=1
                    // A/D/MREG=0
                    // (z^(i+3)+z^(i+5)z^-8)(z^-8)(z^-8) = (z^i)(z^-13 + z^-19)
                    //                       reg  preadd
                    // (z^(i+3)z^-8+z^(i+5))(z^-8)(z^-8) = (z^i)(z^-11 + z^-21)
                    //                       reg  preadd
                    fir_dsp_core #(.AREG(0),.DREG(0),.MULT_REG(0),
                                   .PREADD_REG(1),.CREG(1),.PREG(1),
                                   .ADD_PCIN("FALSE"),
                                   .USE_C("TRUE"),
                                   .SUBTRACT_A("TRUE"))
                        u_i11_13( .clk_i(clk_i),
                                  .a_i(`QCONV( A13x2, 14, 0, 17, 9)),
                                  .d_i(`QCONV( A11, 13, 0, 17, 9 )),
                                  .b_i( b_coeff11_13 ),
                                  // We want (A13 * 2^7 * 2^-15) = (A13 * 2^-8)
                                  .c_i(`QCONV( A13, 5, 8, 24, 24 )),
                                  .pcout_o( i11_13_to_i5_7 ));
                end else begin : STRUCT0B
                    // A13 computation...
                    reg [NBITS:0] A13 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay2 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay3 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay4 = {NBITS+1{1'b0}};
                    reg [NBITS:0] A13_delay5 = {NBITS+1{1'b0}};
                    
                    reg [NBITS-1:0] a13_del1 = {NBITS{1'b0}};
                    reg [NBITS-1:0] a13_del2 = {NBITS{1'b0}};
                    reg [NBITS-1:0] a13_del3 = {NBITS{1'b0}};
                    // 2A13
                    wire [NBITS+1:0] A13_x2 = { A13, 1'b0 };
                    // -2A13 plus x[i-3]
                    reg [NBITS+2:0] x_minus_A13_x2 = {NBITS+3{1'b0}};
                    reg [NBITS+2:0] x_minus_del1 = {NBITS+3{1'b0}};
                    reg [NBITS+2:0] x_minus_del2 = {NBITS+3{1'b0}};
                    //  and A13_store
                    reg [NBITS:0] A13_store = {NBITS+1{1'b0}};
                    
                    always @(posedge clk_i) begin : PREADD_11_13
                        A13_delay <= { xin[i+3][NBITS-1], xin[i+3] } +
                               { xin[i-3][NBITS-1], xin[i-3] };
                        A13_delay2 <= A13_delay;
                        A13_delay3 <= A13_delay2;
                        A13_delay4 <= A13_delay3;
                        A13_delay5 <= A13_delay4;
                        A13 <= A13_delay;
                        // need to sign extend 3 bits and 1 bits respectively
                        x_minus_A13_x2 <= { {3{xin[i-3][NBITS-1] }}, xin[i-3] } -
                                          { A13_x2[NBITS+1], A13_x2};
                        x_minus_del1 <= x_minus_A13_x2;
                        x_minus_del2 <= x_minus_del1;
                        
                        a13_del1 <= xin_store[i+3];
                        a13_del2 <= a13_del1;
                        a13_del3 <= a13_del2;
                    end
                    // AREG=2
                    // M/CREG=1
                    // AD/D/PREG=0
                    fir_dsp_core #(.AREG(2),
                                   .MULT_REG(1),.CREG(1),
                                   .DREG(0),.PREADD_REG(0),.PREG(0),
                                   .ADD_PCIN("FALSE"),
                                   .USE_C("TRUE"),
                                   .SUBTRACT_A("FALSE"))
                        u_i11_13( .clk_i(clk_i),
                                  .a_i(`QCONV( a13_del3, 12, 0, 17, 9)),
                                  .d_i(`QCONV( x_minus_del2, 15, 0, 17, 9)),
                                  .b_i( b_coeff11_13 ),
                                  // We want (A13 * 2^7 * 2^-15) = (A13 * 2^-8)
                                  .c_i(`QCONV( A13_delay5, 5, 8, 24, 24 )),
                                  .pcout_o( i11_13_to_i5_7 ));                  
                    
                end                                                       
                ///////////////////////////////////
                //             TAP 5/7           //
                ///////////////////////////////////
                
                // merge the short-delay samples. Sign extend first                
                wire [NBITS+1:0] A_short_in0_x2 = { {xin[i+1][NBITS-1]}, xin[i+1], 1'b0 };
                wire [NBITS+1:0] A_short_in1 =    { {2{ xin[i+3][NBITS-1]}}, xin[i+3] };
                reg [NBITS+1:0] A_short = {NBITS+2{1'b0}};
                // merge the long-delay samples. Sign extend first
                wire [NBITS+1:0] A_long_in0_x2 = (i == 0) ?
                    { xin_store[i+7][NBITS-1], xin_store[i+7], 1'b0 } :
                    { xin[i-1][NBITS-1], xin[i-1], 1'b0 };
                wire [NBITS+1:0] A_long_in1 = ( i < 3 ) ?                
                    { {2{ xin_store[i+5][NBITS-1]}}, xin_store[i+5] } :
                    { {2{ xin[i-3][NBITS-1]}}, xin[i-3] };
                reg [NBITS+1:0] A_long = {NBITS+2{1'b0}};
                reg [NBITS+1:0] a_del1 = {NBITS+2{1'b0}};
                reg [NBITS+1:0] a_del2 = {NBITS+2{1'b0}};
                reg [NBITS+1:0] a_del3 = {NBITS+2{1'b0}};
                reg [NBITS+1:0] a_del4 = {NBITS+2{1'b0}};
                reg [NBITS+1:0] d_del1 = {NBITS+2{1'b0}};
                reg [NBITS+1:0] d_del2 = {NBITS+2{1'b0}};
                reg [47:0] pci_del1 = {48{1'b0}};
                              
                always @(posedge clk_i) begin : PREADD_5_7
                    a_del1 <= A_long;
                    a_del2 <= a_del1;
                    a_del3 <= a_del2;
                    a_del4 <= a_del3;
                    d_del1 <= A_short;
                    d_del2 <= d_del1;
                    A_short <= A_short_in0_x2 - A_short_in1;
                    A_long <= A_long_in0_x2 - A_long_in1;
                end
                
                // AREG=2
                // AD/PREG = 1
                // D/MREG = 0
                fir_dsp_core #(.AREG(2),.PREADD_REG(1),.PREG(1),
                               .DREG(0),.MULT_REG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("FALSE"),
                               .SUBTRACT_A("FALSE"))
                    u_i5_7( .clk_i(clk_i),
                           .a_i( `QCONV( a_del4 , 13, 0, 17, 9) ),
                           .d_i( `QCONV( d_del2, 13, 0, 17, 9) ),
                           .b_i( b_coeff5_7 ),
                           .pcin_i( i11_13_to_i5_7 ),
                           .pcout_o( i5_7_to_i1_3 ));
                
                ///////////////////////////////////
                //             TAP 1/3           //
                ///////////////////////////////////
                
                // construct A3
                reg [NBITS:0] A3 = {NBITS+1{1'b0}};
                reg [NBITS:0] A3_del1 = {NBITS+1{1'b0}};
                reg [NBITS:0] A3_del2 = {NBITS+1{1'b0}};
                // construct A1
                reg [NBITS:0] A1 = {NBITS+1{1'b0}};
                reg [NBITS:0] A1_del1 = {NBITS+1{1'b0}};
                reg [NBITS:0] A1_del2 = {NBITS+1{1'b0}};
                
                // A1 is made from
                // 0:   xin_store[i+7] + xin_delay[i+1]
                // 1-4: xin[i-1] + xin_delay[i+1]
                wire [NBITS-1:0] A1_in0 = (i == 0) ? xin_store[i+7] : xin[i-1];
                wire [NBITS-1:0] A1_in1 = xin_delay[i+1];
                // A3 is made from
                // 0-2: xin_store[i+5] + xin_delay[i+3]
                // 4-5: xin[i-3] + xin_delay[i+3]
                wire [NBITS-1:0] A3_in0 = (i < 3) ? xin_store[i+5] : xin[i-3];
                wire [NBITS-1:0] A3_in1 = xin_delay[i+3];
                
                always @(posedge clk_i) begin : PREADD_1_3
                    A1 <= { A1_in0[NBITS-1], A1_in0 } +
                          { A1_in1[NBITS-1], A1_in1 };
                    A3 <= { A3_in0[NBITS-1], A3_in0 } +
                          { A3_in1[NBITS-1], A3_in1 };
                    A1_del1 <= A1;
                    A1_del2 <= A1_del1;
                    A3_del1 <= A3;
                    A3_del2 <= A3_del1;
                end
                // M/CREG = 1
                // A/D/AD/PREG=0
                // Multiplier gets preferenced over preadder because of the chain up to
                // i5/7
                fir_dsp_core #(.MULT_REG(1),.CREG(1),
                               .AREG(0),.DREG(0),.PREADD_REG(0),.PREG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("TRUE"),
                               .SUBTRACT_A("FALSE"))
                    u_i1_3( .clk_i(clk_i),
                           .a_i(`QCONV(A3_del1, 13, 0, 17, 9) ),
                           .d_i(`QCONV(A1_del1, 13, 0, 17, 9) ),
                           .b_i(b_coeff1_3),
                           // we want (A3 << 7) >> 15 = A3 >> 8
                           .c_i(`QCONV(A3_del1, 5, 8, 24, 24)),
                           .pcin_i( i5_7_to_i1_3 ),
                           .pcout_o( i1_3_to_i15 ));
                
                ///////////////////////////////////
                //             TAP 15/9          //
                ///////////////////////////////////
                
                // Taps 15/9 cascade one input.
                // For sample 0, the i15 inputs are A: xin_store[i+7] and D: xin_store[i+1]
                // sample 1-4 have A: xin[i-1] and D: xin_store[i+1]
                // i9 A input is cascade
                // i9 D input is xin_delay[i+1]
                // i9 C input is xin_delay[i]
                
                wire [11:0] Ain_i15 = (i == 0) ? xin_store[i+7] : xin[i-1];
                reg [11:0] a15_del1 = {12{1'b0}};
                reg [11:0] a15_del2 = {12{1'b0}};
                reg [11:0] a15_del3 = {12{1'b0}};
                reg [11:0] a15_del4 = {12{1'b0}};
                reg [11:0] d15_del1 = {12{1'b0}};
                reg [11:0] d15_del2 = {12{1'b0}};
                reg [11:0] d15_del3 = {12{1'b0}};
                reg [11:0] d9_del1 = {12{1'b0}};
                reg [11:0] d9_del2 = {12{1'b0}};
                reg [11:0] c9_del1 = {12{1'b0}};
                 always @(posedge clk_i) begin : Delay_15_9
                 a15_del1 <= Ain_i15;
                 a15_del2 <= a15_del1;
                 a15_del3 <= a15_del2;
                 a15_del4 <= a15_del3;
                 d15_del1 <= xin_store[i+1];
                 d15_del2 <= d15_del1;
                 d15_del3 <= d15_del2;
                 d9_del1 <= xin_delay[i+1];
                 c9_del1 <= xin_delay[i];
                 end
                // AREG/ACASCREG=2
                // AD/D/M/PREG=1
                fir_dsp_core #(.USE_ACOUT("TRUE"),
                               .AREG(2),.ACASCREG(2),
                               .DREG(1),.PREADD_REG(1),.MULT_REG(1),.PREG(1),
                               .ADD_PCIN("TRUE"),
                               .USE_C("FALSE"))
                    u_i15( .clk_i(clk_i),
                           .a_i(`QCONV(a15_del3, 12, 0, 17, 9)),
                           .d_i(`QCONV(d15_del2, 12, 0, 17, 9)),
                           .b_i(b_coeff15),
                           .acout_o( i15_to_i9_acin ),
                           .pcin_i( i1_3_to_i15 ),
                           .pcout_o( i15_to_i9 ));                
                fir_dsp_core #(.USE_ACIN("TRUE"),
                               .AREG(0),.DREG(1),.CREG(0),.MULT_REG(1),.PREG(1),
                               .PREADD_REG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("TRUE"))
                    u_i9( .clk_i(clk_i),
                          .acin_i( i15_to_i9_acin),
                          .d_i(`QCONV(xin_delay[i+1], 12, 0, 17, 9)),
                          .b_i(b_coeff9),
                          // we want xin_delay[i] << 14 >> 15 = >> 1
                          .c_i(`QCONV(xin_delay[i], 11, 1, 24, 24)),
                          .pcin_i(i15_to_i9 ),
                          .p_o( sample_out[i] ));
                  
            end 
            //unused else begin : STRUCT1 end
            if (i < 5) begin : ADD_DELAY
                reg [OUTQ_INT+OUTQ_FRAC-1:0] out_delay = {(OUTQ_INT+OUTQ_FRAC){1'b0}};
                always @(posedge clk_i) begin : ADD_DELAY_LOGIC
                    // NOTE NOTE NOTE NOTE NOTE NOTE NOTE
                    // I SHOULD PROBABLY DEAL WITH UNDERFLOW/OVERFLOW HERE
                    out_delay = sample_out[i][ (24-OUTQ_FRAC) +: (OUTQ_INT+OUTQ_FRAC) ];
                end
                assign out_o[(OUTQ_INT+OUTQ_FRAC)*(i+4) +: (OUTQ_INT+OUTQ_FRAC)] = out_delay;
            end 
            // unused else begin : NODELAY            
        end
    endgenerate
    reg [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] out_o_store;
    always @(posedge clk_i) 
    begin
            out_o_store <= out_o[(OUTQ_INT+OUTQ_FRAC)*2*NSAMPS-1:(OUTQ_INT+OUTQ_FRAC)*NSAMPS];
            out_valid <= ~out_valid;
    end
    assign out_o [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] = out_o_store;
    
    
endmodule
