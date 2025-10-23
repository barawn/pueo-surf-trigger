`timescale 1ns / 1ps
// Matched filter for the 1500 MSa/s filter chain.
module matched_filter_v3_1500 #(parameter INBITS=12,
                                parameter NSAMPS=4)(
        input aclk,
        input [INBITS*NSAMPS-1:0] data_i,
        output [INBITS*NSAMPS-1:0] data_o
    );
    
    wire signed [NSAMPS-1:0][INBITS-1:0] din;
    // Start off by generating the preadd.
    reg [NSAMPS-1:0][INBITS:0] preadd = { NSAMPS*(INBITS+1){1'b0}};
    // Preadd needs a store to wrap around.
    reg signed [NSAMPS-1:0][INBITS:0] preadd_store = { NSAMPS*(INBITS+1){1'b0}};
    // The preadd is obviously delayed by 1 clock due to the add, so we need to
    // additionally store data. We also need a second storage for the later samples too.
    reg signed [NSAMPS-1:0][INBITS-1:0] store = { NSAMPS*INBITS{1'b0}};
    // double store
    reg signed [NSAMPS-1:0][INBITS-1:0] sstore = { NSAMPS*INBITS{1'b0}};

    // sample 0:
    // Then the bottom DSP gets a ternary adder with:
    // (-4preadd[i+1] -2store[i+2] + sstore[i])z^-4 (extra AB reg=2?)
    // and another with
    // preadd[i] + 2store[i+2] + 2store[i+3] (C input = CREG=1?)
    // and the next DSP gets (maybe AB=1 and C=0?)
    // (data[i+3] + preadd[i] - preadd[i+2])z^-4 (extra AB reg)
    // and
    // (-data[i] + data[3] - store[i+1])
    //
    // this gives us
    // -1 + z^-3 - z^-1z^-4 + (z^-3z^-4) + (1-z^-1)z^-4z^-4 - (1-z^-1)z^-2z^-4z^-4
    // + (1+z^-1)z^-4z^-4z^-4 + 2z^-2z^-4z^-4z^-4 + 2z^-3z^-4z^-4z^-4) + 
    // yeah I think this works
    
    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : S
            // low DSP gets -4z^-17(1-z^-1) - 2z^-19 + z^-20.
            // max is 4*4095 + 4096 + 2048 = 20680 which is 14.33 bits, needs INBITS+4
            reg signed [(INBITS+4)-1:0] lowsumA = {(INBITS+4){1'b0}};
            // and next is z^-12 - z^-13 + 2z^-14 + 2z^-15 which maxes at 12280 = 15 bits
            reg signed [(INBITS+3)-1:0] lowsumB = {(INBITS+3){1'b0}};
            // high DSP gets z^-7 + (1-z^-1)z^-8 + (1-z^-1)z^-10
            // maxes at 10238 = 15 bits
            reg signed [(INBITS+3)-1:0] highsumA = {(INBITS+3){1'b0}};
            // and the last is just -1+z^-3+z^-5 which maxes at just 6144 = 14 bits
            reg signed [(INBITS+2)-1:0] highsumB = {(INBITS+2){1'b0}};            

            // Let's just try this in fabric and see what happens at first.
            // The low sum is 16 bits + 15 bits, going to JUST OVER 16 bits sigh
            reg signed [(INBITS+4)-1:0] lowsumA_store = {(INBITS+4){1'b0}};
            reg signed [(INBITS+4)-1:0] lowsumA_store2 = {(INBITS+4){1'b0}};
            reg signed [(INBITS+3)-1:0] lowsumB_store = {(INBITS+3){1'b0}};
            reg signed [(INBITS+5)-1:0] lowsum = {(INBITS+5){1'b0}};
            
            reg signed [(INBITS+3)-1:0] highsumA_store = {(INBITS+3){1'b0}};

            // and the final highsum is 12280 + 20680 + 10238 + 6144 = still 17 bits
            reg signed [(INBITS+5)-1:0] highsum = {(INBITS+5){1'b0}};
            // We divide by 16, so we're actually only looking at highsum[16:4]
            // we want to use [15:4] so we need to saturate out the top bit.
            // This is expected since the abs sum of the taps is 25, and after
            // dividing by 16 that leaves us just barely over 1.
            reg [INBITS-1:0] highsum_sat = {INBITS{1'b0}};
            
            assign din[i] = data_i[INBITS*i +: INBITS];
            
            // depressing amounts of manual sign extension because it NEVER GODDAMN WORKS
            // lowsumA is 16 bits
            wire [11:0] lowsumA_0 = sstore[i];
            wire [12:0] lowsumA_1 = (i>0) ? preadd[i-1] : preadd_store[i+3];
            wire [11:0] lowsumA_2 = (i>2) ? store[i-3] : sstore[i+1];            
            wire [15:0] lowsumA_0_SE = { {4{lowsumA_0[11]}}, lowsumA_0 };
            wire [15:0] lowsumA_1_SE = { lowsumA_1[12], lowsumA_1, 2'b00 };
            wire [15:0] lowsumA_2_SE = { {3{lowsumA_2[11]}}, lowsumA_2, 1'b0 };
            
            // lowsumB is 15 bits
            wire [12:0] lowsumB_0 = preadd[i];
            wire [11:0] lowsumB_1 = (i>1) ? store[i-2] : sstore[i+2];
            wire [11:0] lowsumB_2 = (i>2) ? store[i-3] : sstore[i+1];
            wire [14:0] lowsumB_0_SE = { {2{lowsumB_0[12]}}, lowsumB_0 };
            wire [14:0] lowsumB_1_SE = { {2{lowsumB_1[11]}}, lowsumB_1, 1'b0 };
            wire [14:0] lowsumB_2_SE = { {2{lowsumB_2[11]}}, lowsumB_2, 1'b0 };
                                    
            // highsumA is 15 bits
            wire [12:0] highsumA_0 = preadd[i];
            wire [11:0] highsumA_1 = (i>2) ? din[i-3] : store[i+1];
            wire [12:0] highsumA_2 = (i>1) ? preadd[i-2] : preadd_store[i+2];
            wire [14:0] highsumA_0_SE = { {2{highsumA_0[12]}}, highsumA_0 };
            wire [14:0] highsumA_1_SE = { {3{highsumA_1[11]}}, highsumA_1 };
            wire [14:0] highsumA_2_SE = { {2{highsumA_2[12]}}, highsumA_2 };
            
            // highsumB is 14 bits
            wire [11:0] highsumB_0 = ((i>2) ? din[i-3] : store[i+1]);
            wire [11:0] highsumB_1 = din[i];
            wire [11:0] highsumB_2 = ((i>0) ? store[i-1] : sstore[i+3]);
            wire [13:0] highsumB_0_SE = { {2{highsumB_0[11]}}, highsumB_0 };
            wire [13:0] highsumB_1_SE = { {2{highsumB_1[11]}}, highsumB_1 };
            wire [13:0] highsumB_2_SE = { {2{highsumB_2[11]}}, highsumB_2 };
            
                       
            always @(posedge aclk) begin : P
                store[i] <= din[i];
                sstore[i] <= store[i];
                // preadd is 1+z^-1
                preadd[i] <= {din[i][11],din[i]} - ((i > 0) ? 
                        {din[i-1][11],din[i-1]} : 
                        {store[i+3][11], store[i+3]});
                preadd_store[i] <= preadd[i];
                
                // Sign extension seems to act weird for some reason here.
                // So just do it depressingly manually.
                
                // lowsumA is 16 bits.
                // sstore[i] - 4*preadd[i-1] - 2*store[i-3]
                lowsumA <= lowsumA_0_SE - lowsumA_1_SE - lowsumA_2_SE;
                // preadd[i] + 2store[i-2] + 2store[i-3]
                // sigh. lowsumB is 15 bits
                lowsumB <= lowsumB_0_SE + lowsumB_1_SE + lowsumB_2_SE;
                
                // preadd[i] + din[i-3] - preadd[i-2]
                // highsumA is 15 bits                       
                highsumA <= highsumA_0_SE + highsumA_1_SE - highsumA_2_SE;
                // -din[i] + din[i-3] -store[i-1]                            
                highsumB <= highsumB_0_SE - highsumB_1_SE - highsumB_2_SE;
                
                lowsumA_store <= lowsumA;
                lowsumA_store2 <= lowsumA_store;
                lowsumB_store <= lowsumB;
                lowsum <= lowsumB_store + lowsumA_store2;
                highsumA_store <= highsumA;
                
                highsum <= highsumA_store + highsumB + lowsum;
                if (^highsum[(INBITS+4-1) +: 2]) begin
                    highsum_sat[INBITS-1] <= highsum[INBITS+5-1];
                    highsum_sat[0 +: (INBITS-1)] <= {(INBITS-1){highsum[INBITS+4-1]}};
                end else begin
                    highsum_sat <= highsum[4 +: INBITS];
                end
            end
            assign data_o[INBITS*i +: INBITS] = highsum_sat;
        end
    endgenerate
endmodule
