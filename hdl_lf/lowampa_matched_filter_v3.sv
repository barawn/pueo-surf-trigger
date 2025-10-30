`timescale 1ns / 1ps
// Second version of a Shannon-Whitaker LP filter.
//
// This version ensures that all DSPs have at least a preadd or multiplier
// register in their path, which should guarantee timing even when the
// FPGA becomes extremely full.
module lowampa_matched_filter_v3 #(parameter NBITS=12,
                                    parameter NSAMPS=4,
                                    parameter OUTQ_INT=12,
                                    parameter OUTQ_FRAC=0)(
        input clk_i,
        input [NBITS*NSAMPS-1:0] in_i,
        output [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] out_o
    );
    
    // for ease of use
    wire [NBITS-1:0] xin[NSAMPS-1:0];
    generate
        genvar ii,jj;
        for (ii=0;ii<NSAMPS;ii=ii+1) begin : S
            for (jj=0;jj<NBITS;jj=jj+1) begin : B
                assign xin[ii][jj] = in_i[NBITS*ii + jj];
            end
        end
    endgenerate   

   //localparam taps = [1,1,1,1,0,0,0,0,0,-1,-1,-1,-1,-1,-1,-1,-1,0,0,0,1,1,1,1,1,1,1,1,0,0,-1,-1,-2,-2,-2,-2,-1,0,0,1,2,2,2,2,2,1,0,-1,-2,-2,-2,-2,-2,-1,1,2,2,4,2,2,0,-2,-4,-4,-2,0,2,4,4,2,-1,-2,-4,-1,4,4,-1,-4,0,1]
   //localparam helper = [1,1,1,1]
   //localparam helper_taps = [1,0,0,0,0,0,0,0,0,-1,0,0,0,-1,0,0,0,0,0,0,1,0,0,0,1,0,0,0,0,0,-1,0,-1,0,-1,0,0,0,0,1,1,0,0,0,0,0,0,-1,-1,0,0,-1,0,0,2,0,0,2,0,0,-2,0,-2,0,0,2,0,2,0,0,-2,0,0,0,0,0,0,0,0,0]
   //localparam remaining_taps = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,2,1,0,0,0,0,0,0,-1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,0,-2,1,4,4,-1,-4,0,1]
   localparam negative_adjust = 3; //need to add 1 every time we do 1's complement to invert
   localparam delayed_store_size = 19;

   //helper constructor generates 
   //0:[1 1]
   //1:[0 1 1]
   //2:[0 0 1 1]
   //3:[0 0 0 1 1]
   //4:[0 0 0 0 1 1]
   //5:[0 0 0 0 0 1 1]
   //helper is then 
   //0:[1 1 1 1] constructor 0+2
   //1:[0 1 1 1 1] constructor 1+3
   //2:[0 0 1 1 1 1] constructor 2+4
   //3:[0 0 0 1 1 1 1] constructor 3+5
   //this costs 6 nbits-1 adds and 4 nbits adds, as opposed to 8 nbits-1 adds and 4 nbits adds by doing the 4 way add 3 times

   reg [NBITS-1:0] delayed_inputs [delayed_store_size-5:0]; //used to calculate delayed values
   reg [NBITS+1:0] delayed_helper [delayed_store_size-9:0]; //used to calculate delayed values
   reg [NBITS:0] helper_constructor [5:0]; //used to calculate helper
   wire [NBITS-1:0] delay_x_array_unsynched [delayed_store_size-1:0]; //delayed inputs
   wire [NBITS-1+8:0] delay_y_array [delayed_store_size-9:0]; //delayed sum of 4 consecutive inputs, sign extend
   wire [NBITS-1+8:0] delay_x_array [delayed_store_size-9:0]; //delayed inputs synch to delay_y_array, sign extend
   
   assign delay_x_array_unsynched[0] = xin[3];
   assign delay_x_array_unsynched[1] = xin[2];
   assign delay_x_array_unsynched[2] = xin[1];
   assign delay_x_array_unsynched[3] = xin[0];

   //copy input data delayed 4 spaces along
   generate
     genvar j;
     for (j=0;j<delayed_store_size-4;j=j+1)
       begin
	     assign delay_x_array_unsynched[j+4] = delayed_inputs[j];
         assign delay_x_array[j][NBITS-1:0] = delay_x_array_unsynched[j+8];
         assign delay_x_array[j][NBITS-1+8:NBITS-1+1] = {8{delay_x_array_unsynched[j+8][NBITS-1]}};
	     assign delay_y_array[j][NBITS+1:0] = delayed_helper[j];
	     assign delay_y_array[j][NBITS-1+8:NBITS+1+1] = {6{delayed_helper[j][NBITS+1]}};
	 
	 always @(posedge clk_i)
	 begin
           if(j<6)
           begin
	     helper_constructor[j] <= {delay_x_array_unsynched[j][NBITS-1],delay_x_array_unsynched[j]}+{delay_x_array_unsynched[j+1][NBITS-1],delay_x_array_unsynched[j+1]};
	       end
	   delayed_inputs[j] <= delay_x_array_unsynched[j];
	   if(j<4)
           begin
	     delayed_helper[j] <= {helper_constructor[j][NBITS],helper_constructor[j]}+{helper_constructor[j+2][NBITS],helper_constructor[j+2]};
	   end
	   else
           begin
	     delayed_helper[j] <= delayed_helper[j-4];
           end
	 end
       end
   endgenerate


    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : filter
	    reg [NBITS-1+1:0] sum01; //2=2^1
	    reg [NBITS-1+1:0] sum02div4; //8/4=2=2^1
	    reg [NBITS-1+4:0] sum03; //10<2^4
	    reg [NBITS-1+4:0] sum03del; //10<2^4
	    reg [NBITS-1+3:0] sum04div2; //16/2=8=2^3
	    reg [NBITS-1+5:0] sum05; //26<2^5
	    reg [NBITS-1+6:0] sum06; //34<2^6
	    reg [NBITS-1+6:0] sum07; //42<2^6
	    reg [NBITS-1+7:0] sum08; //75<2^7
	    reg [NBITS-1+7:0] sum08del; //75<2^7
	    reg [NBITS-1+2:0] sum09; //3<2^2
	    reg [NBITS-1+3:0] sum10; //5<2^3
	    reg [NBITS-1+7:0] sum11; //78<2^7
	    reg [NBITS-1+7:0] sum12; //83<2^7
	    reg [NBITS-1+3:0] sum13; //5<2^3
	    reg [NBITS-1+7:0] sum14; //88<2^7
	    reg [NBITS-1+7:0] sum14del; //88<2^7
	    reg [NBITS-1+7:0] sum14del2; //88<2^7
	    reg [NBITS-1+7:0] sum15; //112<2^7
	    reg [NBITS-1+3:0] sum16; //8=2^3
	    reg [NBITS-1+7:0] sum17; //120<2^7
	    reg [NBITS-1+7:0] sum17del; //120<2^7
	    reg [NBITS-1+7:0] sum18; //128=2^7
	    reg [NBITS-1+7:0] sum19; //129>2^7, but our sum of taps is 114, so need 7 bits max because of cancellations
	    reg [NBITS-1+7:0] sum20; //133>2^7, but our sum of taps is 114, so need 7 bits max because of cancellations

	    reg [NBITS-1+3:0] sumn1; //5<2^3
	    reg [NBITS-1+3:0] sumn2; //7<2^3
	    reg [NBITS-1+4:0] sumn3; //9<2^4
	    reg [NBITS-1+4:0] sumn4; //16=2^4
	    reg [NBITS-1+4:0] sumn4del; //16=2^4
	    reg [NBITS-1+3:0] sumn5div2; //16/2=8=2^3
	    reg [NBITS-1+5:0] sumn6; //32=2^5
	    reg [NBITS-1+6:0] sumn7; //33<2^6
	    reg [NBITS-1+3:0] sumn8; //8=2^3
	    reg [NBITS-1+4:0] sumn9; //12<2^4
	    reg [NBITS-1+4:0] sumn9del; //12<2^4
	    reg [NBITS-1+4:0] sumn9del2; //12<2^4
	    reg [NBITS-1+4:0] sumn9del3; //12<2^4
	    reg [NBITS-1+4:0] sumn9del4; //12<2^4
	    reg [NBITS-1+3:0] sumn10; //8=2^3
	    reg [NBITS-1+4:0] sumn11; //12<2^4
	    reg [NBITS-1+5:0] sumn12; //24<2^5
	    reg [NBITS-1+3:0] sumn13; //8=2^3
	    wire [NBITS-1:0] finalsumdiv16_saturated;
        always @(posedge clk_i)
        begin
	    //comment is maximum size relative to input maximum
	    //add negatives before inverting where resonable
            sumn1 <= delay_x_array[4+i] + {delay_x_array[5+i],2'b0}; //-5, 76 and 77 after 18 delays
	        sumn2 <= sumn1 + {delay_x_array[4+i],1'b0}; //-7, 72 after 17 delays
    	    sumn3 <= delay_x_array[2+i] + {delay_y_array[2+i],1'b0}; //-9, 70 after 17 delays
    	    sumn4 <=sumn3+{sumn2[NBITS+2],sumn2}; //-16
    	    sumn4del <= sumn4; //-16
    	    sumn5div2 <= delay_y_array[2+i] + delay_y_array[0+i]; // -8+-8=-16/2=-8, 62 and 60 after 15 delays
    	    sumn6 <= {sumn4del[NBITS+3],sumn4del} + {sumn5div2[NBITS+2],sumn5div2,1'b0}; //-32
    	    sumn7 <= {sumn6[NBITS+4],sumn6} + delay_x_array[0+i]; // -33, 52 after 13 delays
    	    
    	    sumn8 <= delay_y_array[0+i] + delay_y_array[3+i]; // -4+-4=-8, 48 and 51 after 12 delays
    	    sumn9 <= {sumn8[NBITS+2],sumn8} + delay_y_array[3+i]; // -8+-4=-12, 47 after 11 delays
    	    sumn9del <= sumn9; //-12
    	    sumn9del2 <= sumn9del; //-12
    	    sumn9del3 <= sumn9del2; //-12
    	    sumn9del4 <= sumn9del3; //-12
    	    sumn10 <= delay_y_array[2+i] + delay_y_array[0+i]; // -4+-4=-8, 34 and 32 after 8 delays
            sumn11 <= {sumn10[NBITS+2],sumn10} + delay_y_array[2+i]; // -8+-4=-12, 30 after 7 delays
    	    sumn12 <= {sumn11[NBITS+3],sumn11} + {sumn9del4[NBITS+3],sumn9del4}; //-24

	        sumn13 <= delay_y_array[1+i] + delay_y_array[5+i]; //-4+-4=-8, 9 and 13 after 2 delays


    	    sum01 <= delay_x_array[7+i] + delay_x_array[1+i];  //2, 73 and 79 after 18 delays
            sum02div4 <= delay_x_array[2+i] + delay_x_array[3+i]; //4+4=8/4=2, 74 and 75 after 18 delays, left shift sum after add
            sum03 <= {{3{sum01[NBITS]}},sum01}+{sum02div4[NBITS],sum02div4,2'b0}; //10
            sum03del <= sum03;
    	    sum04div2 <= delay_y_array[1+i] + delay_y_array[3+i]; // 8+8=16/2=8,65 and 67 after 16 delays , leftshift sum after add
    	    sum05 <= {sum03del[NBITS+3],sum03del}+{sum04div2[NBITS+2],sum04div2,1'b0}; //26
    	    sum06 <= {sum05[NBITS+4],sum05} + {delay_y_array[1+i],1'b0}; //34, 57 with 14 delays
    	    sum07 <= sum06 + {delay_y_array[2+i],1'b0}; // 42, 54 with 13 delays
    	    sum08 <= {sum07[NBITS+5],sum07} + ~{sumn7[NBITS+5],sumn7}; //42+33 = 75
    	    sum08del <= sum08; //75
            sum09 <= {delay_x_array[0+i],1'b0} + delay_x_array[1+i]; //3, 44 and 45 with 11 delays
            sum10 <= delay_x_array[3+i] + delay_y_array[0+i]; // 1+4=5, 40 and 43 with 10 delays
            sum11 <= {{5{sum09[NBITS+1]}},sum09}+sum08del;//78
    	    sum12 <= {{2{sum11[NBITS+5]}},sum11}+{{5{sum10[NBITS+2]}},sum10}; //83
	        sum13 <= delay_y_array[3+i] + delay_x_array[1+i]; //4+1=5, 37 and 39 with 9 delays
            sum14 <= {{5{sum13[NBITS+2]}},sum13}+sum12; //88
    	    sum14del <=sum14;//88
    	    sum14del2 <=sum14del; //88
    	    sum15 <= sum14del2+~{{3{sumn12[NBITS+4]}},sumn12}; //88+24=112
    	    sum16 <= delay_y_array[0+i] + delay_y_array[4+i]; // 4+4=8, 20 and 24 with 5 delays
    	    sum17 <= {{5{sum16[NBITS+2]}},sum16}+sum15; //120
    	    sum17del <= sum17; //120
	        sum18 <= sum17del + negative_adjust; //120+small number
	        sum19 <= sum18 +~{{4{sumn13[NBITS+2]}},sumn13}; //120+small number+8=128 +small number
	        sum20 <= sum19 + delay_y_array[0+i]; //132+small number
	    end
	    //divide by 16 mean we left shift 4, but we added 7 bits, so we need to check if the leftmost 4 bits are still the same, if they are not we have overflowed the output and must saturate
            assign finalsumdiv16_saturated[OUTQ_INT-1] = sum20[NBITS+6]; //preserve sum
            assign finalsumdiv16_saturated[OUTQ_INT-2:0] = (sum20[NBITS+5:NBITS+3] == {3{sum20[NBITS+6]}})? //did we overflow
		                                                   (sum20[NBITS+2:4]): //if we didnt, keep current values in range 4+[NBITS-2:0]
							                               ({(OUTQ_INT-1){~sum20[NBITS+6]}}); //if we did, replace value with max/min value 100000000000 or 011111111111
	    
            assign out_o[(OUTQ_INT+OUTQ_FRAC)*(NSAMPS-1-i) +: (OUTQ_INT+OUTQ_FRAC)] = finalsumdiv16_saturated;
        end
    endgenerate
    
    
endmodule
