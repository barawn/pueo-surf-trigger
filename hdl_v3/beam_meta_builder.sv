`timescale 1ns / 1ps
`include "pueo_beams_09_04_25.sv"
`include "pueo_dummy_beams.sv"

import pueo_beams::NUM_BEAM;
import pueo_dummy_beams::NUM_DUMMY;

// super silly
import pueo_beams::META0_INDICES;
import pueo_beams::META1_INDICES;
import pueo_beams::META2_INDICES;
import pueo_beams::META3_INDICES;
import pueo_beams::META4_INDICES;
import pueo_beams::META5_INDICES;
import pueo_beams::META6_INDICES;
import pueo_beams::META7_INDICES;

module beam_meta_builder #(parameter FULL = "TRUE",
                           parameter USE_V3 = "TRUE",
                           localparam NBEAMS = (FULL == "TRUE") ? NUM_BEAM : NUM_DUMMY)(
        input clk_i,
        input [NBEAMS-1:0] beam_i,
        input trig_i,
        output [7:0] meta_o,
        output       trig_o
    );
    
    // The meta builder takes in the output of the trigger generator, which is
    // both the single trigger bit plus up to 48 masked trigger bits from the
    // individual beams.
    // The meta builder generates the 8 bit metadata from those bits and forwards the
    // trigger onward.
    
    generate
        genvar n, b, idx;
        if (USE_V3 == "FALSE") begin : NM
            // Prior to V3 we just directly pass it forward.
            assign meta_o = 8'h00;
            assign trig_o = trig_i;
        end else begin : M
            // The meta generation takes 2 clocks (one to clock into AB or C, one to generate P)
            // so redelay the trigger by 2 clocks.
            reg [1:0] trig_rereg = {2{1'b0}};
            always @(posedge clk_i) begin : TL
                trig_rereg <= { trig_rereg[0], trig_i };
            end
            assign trig_o = trig_rereg[1];
            if (FULL == "TRUE") begin : META
                localparam int indices[0:7][0:21] =  { META0_INDICES,
                                                       META1_INDICES,
                                                       META2_INDICES,
                                                       META3_INDICES,
                                                       META4_INDICES,
                                                       META5_INDICES,
                                                       META6_INDICES,
                                                       META7_INDICES };
                for (n=0;n<2;n=n+1) begin : NYB
                    wire [3:0][21:0] in_bits;
                    for (b=0;b<4;b=b+1) begin : BL                    
                        for (idx=0;idx<22;idx=idx+1) begin : IL
                            localparam int this_beam = indices[4*n+b][idx];
                            if (this_beam < NBEAMS) begin : RL
                                assign in_bits[b][idx] = beam_i[this_beam];
                            end else begin : FK
                                assign in_bits[b][idx] = 1'b0;
                            end
                        end
                    end
                    beam_meta_nybble u_nyb(.clk_i(clk_i),
                                           .bit0_i(in_bits[0]),
                                           .bit1_i(in_bits[1]),
                                           .bit2_i(in_bits[2]),
                                           .bit3_i(in_bits[3]),
                                           .meta_o(meta_o[4*n +: 4]));
                end
            end else begin
                // Fake beams just get 0xFF for their meta.
                assign meta_o = 8'hFF;
            end
        end
    endgenerate
    
endmodule
