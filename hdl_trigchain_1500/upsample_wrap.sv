`timescale 1ns / 1ps
// Wrap for upsampling using the filter.
module upsample_wrap(
        input clk_i,
        input [47:0] data_i,
        output [95:0] data_o
    );
    
    wire [95:0] to_filter = {
        {12{1'b0}},
        data_i[36 +: 12],
        {12{1'b0}},
        data_i[24 +: 12],
        {12{1'b0}},
        data_i[12 +: 12],
        {12{1'b0}},
        data_i[0 +: 12] };    
    wire [95:0] from_filter;    
    // we need a 12 clock delay = address = 10 in SRL
    // plus FF
    wire [47:0] srlvec_out;
    reg [47:0]  from_srl = {48{1'b0}};
    srlvec #(.NBITS(48))
        u_dly(.clk(clk_i),
              .ce(1'b1),
              .a(4'd10),
              .din(data_i),
              .dout(srlvec_out));
    always @(posedge clk_i) begin
        from_srl <= srlvec_out;
    end
    wire [7:0][12:0] lpf_out_tmp;    
    shannon_whitaker_lpfull_v3
        u_lpf(.clk_i(clk_i),
              .rst_i(1'b0),
              .dat_i(to_filter),
              .dat_o(lpf_out_tmp));
    assign from_filter = {
        lpf_out_tmp[7][11:0],
        lpf_out_tmp[6][11:0],
        lpf_out_tmp[5][11:0],
        lpf_out_tmp[4][11:0],
        lpf_out_tmp[3][11:0],
        lpf_out_tmp[2][11:0],
        lpf_out_tmp[1][11:0],
        lpf_out_tmp[0][11:0] };
        
    assign data_o = {
        from_filter[84 +: 12],  // 7
        from_srl[36 +: 12],     // 6
        from_filter[60 +: 12],  // 5
        from_srl[24 +: 12],     // 4
        from_filter[36 +: 12],  // 3
        from_srl[12 +: 12],     // 2
        from_filter[12 +: 12],  // 1
        from_srl[0 +: 12] };    // 0
            
endmodule
