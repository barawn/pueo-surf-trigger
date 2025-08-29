`timescale 1ns / 1ps
// This pulls out Lucas's sample storage logic so that it can be reused
// as needed.
module sample_store #(parameter NBITS=5,
                      parameter NSAMP=8,
                      parameter SAMPLE_STORE_DEPTH=8+2,
                      parameter PIPE="TRUE")(
        input clk_i,
        input [NSAMP*NBITS-1:0] dat_i,
        output [SAMPLE_STORE_DEPTH*NSAMP*NBITS-1:0] store_o
    );
    
    // If PIPE is true, then none of the outputs are connected to the inputs.
    // If PIPE is false, then the top samples (least delayed) are connected to
    // the inputs directly, which means we need 1 clock less worth of delay.
    localparam REG_DEPTH = (PIPE == "TRUE") ? SAMPLE_STORE_DEPTH : SAMPLE_STORE_DEPTH-1;
    
    reg [REG_DEPTH*NSAMP*NBITS-1:0] sample_store = {REG_DEPTH*NSAMP*NBITS{1'b0}};;
    
    generate
        genvar i;
        if (PIPE != "TRUE") begin : A
            assign store_o[(SAMPLE_STORE_DEPTH-1)*NSAMP*NBITS +: NSAMP*NBITS] = dat_i;
        end
        for (i=REG_DEPTH-2;i>=0;i=i-1) begin : RS
            always @(posedge clk_i) begin : SHIFT_SAMPLE_STORE
                sample_store[i*NSAMP*NBITS +: NSAMP*NBITS] <= sample_store[(i+1)*NSAMP*NBITS +: NSAMP*NBITS];
            end
            assign store_o[i*NSAMP*NBITS +: NSAMP*NBITS] = sample_store[i*NSAMP*NBITS +: NSAMP*NBITS];
        end
        always @(posedge clk_i) begin : NEW_SAMPLE_STORE
            sample_store[(REG_DEPTH-1)*NSAMP*NBITS +: NSAMP*NBITS] <= dat_i;
        end
        assign store_o[(REG_DEPTH-1)*NSAMP*NBITS +: NSAMP*NBITS] = sample_store[(REG_DEPTH-1)*NSAMP*NBITS +: NSAMP*NBITS];
    endgenerate    
endmodule
