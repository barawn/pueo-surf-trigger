`timescale 1ns / 1ps

module sub_beam #(parameter NBITS=5,
                  parameter NSAMP=8,
                  localparam OUTBITS=7)(
        input clk_i,
        input [NBITS*NSAMP-1:0] chA_i,
        input [NBITS*NSAMP-1:0] chB_i,
        input [NBITS*NSAMP-1:0] chC_i,
        output [OUTBITS*NSAMP-1:0] dat_o
    );

    generate
        genvar i;
        for (i=0;i<NSAMP;i=i+1) begin : C
            ternary_add_sub_prim #(.input_word_size(5),
                                   .is_signed(1'b0))
                  u_trpl(.clk_i(clk_i),
                         .rst_i(1'b0),
                         .x_i(chA_i[NBITS*i +: NBITS]),
                         .y_i(chB_i[NBITS*i +: NBITS]),
                         .z_i(chC_i[NBITS*i +: NBITS]),
                         .sum_o(dat_o[OUTBITS*i +: OUTBITS]));
        end
    endgenerate        
endmodule
