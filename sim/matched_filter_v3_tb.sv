`timescale 1ns / 1ps
module matched_filter_v3_tb;

    int fc;

    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    // ADC samples, both indexed and as one array
    reg [11:0] samples [3:0];
    initial begin
        for (int j=0;j<4;j=j+1) samples[j] <= 0;
    end

    wire  [12*4-1:0] sample_arr;
    assign sample_arr ={samples[3],
                        samples[2],
                        samples[1],
                        samples[0] };
    

    wire [11:0] outsample[3:0];
    wire [11*8-1:0] outsample_arr;
    generate
        genvar k;
        for (k=0;k<8;k=k+1) begin : DEVEC
            assign outsample[k] = outsample_arr[12*k +: 12];
        end
    endgenerate
    
    reg [11:0] pretty_insample = {12{1'b0}};    
    reg [11:0] pretty_sample = {12{1'b0}};

    integer pi;
    always @(posedge clk) begin
        fc = $fopen("matched_out.csv","a");
        #0.05;
        pretty_sample <= outsample[0];
        pretty_insample <= samples[0];
        for (pi=1;pi<4;pi=pi+1) begin
            #(5.0/4);
            pretty_sample <= outsample[pi];
            pretty_insample <= samples[pi];
            $fwrite(fc,$sformatf("%d, ",outsample[pi]));
            // $display($sformatf("%d",outsample[pi]));
        end          
        $fclose(fc);
    end

    matched_filter_v3_1500 u_matched_filter(
        .aclk(clk),
        .data_i(sample_arr),
        .data_o(outsample_arr)
    );

    // initial begin

    //     for(int i; i<30000; i++) begin
    //         $display($sformatf("%d",))
    //     end
    // end

    initial begin
        #300;
        @(posedge clk);
            #0.1    samples[0] <= -1024;//12'd1014;//12'd1014;//12'hFFE;
                    samples[1] <= 12'd0;
                    samples[2] <= 12'd0;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= -1024;//12'd1014;//12'hFFE;
                    samples[2] <= 12'd0;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= 12'd0;
                    samples[2] <= -1024;//12'd1014;//12'hFFE;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= 12'd0;
                    samples[2] <= 12'd0;
                    samples[3] <= -1024;//12'd1014;//12'hFFE;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        #300;
        @(posedge clk);
            #0.1    samples[0] <= 1024;//12'd1014;//12'd1014;//12'hFFE;
                    samples[1] <= 12'd0;
                    samples[2] <= 12'd0;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= 1024;//12'd1014;//12'hFFE;
                    samples[2] <= 12'd0;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= 12'd0;
                    samples[2] <= 1024;//12'd1014;//12'hFFE;
                    samples[3] <= 12'd0;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end

        @(posedge clk);
            #0.1    samples[0] <= 12'd0;
                    samples[1] <= 12'd0;
                    samples[2] <= 12'd0;
                    samples[3] <= 1024;//12'd1014;//12'hFFE;
        for(int i=0; i<20; i++) begin
            @(posedge clk);
                #0.1    samples[0] <= 12'd0;
                        samples[1] <= 12'd0;
                        samples[2] <= 12'd0;
                        samples[3] <= 12'd0;
        end
    end                                           
        
endmodule
