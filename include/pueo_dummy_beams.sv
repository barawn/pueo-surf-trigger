`ifndef PUEO_DUMMY_BEAMS_SV
`define PUEO_DUMMY_BEAMS_SV

package pueo_dummy_beams;
   localparam int NUM_DUMMY = 2;

   localparam int SAMPLE_STORE_DUMMY = 3;
   localparam int LEFT_ADDER_LEN_DUMMY = 2;
   localparam int LEFT_STORE_DEPTH_DUMMY = 1;   
   
   localparam int RIGHT_ADDER_LEN_DUMMY = 2;
   localparam int RIGHT_STORE_DEPTH_DUMMY = 1;

   localparam int TOP_ADDER_LEN_DUMMY = 2;
   localparam int TOP_STORE_DEPTH_DUMMY = 1;

   localparam int META0_INDICES_DUMMY[0:21] = '{ 0,
					     1,
					     2,
					     3,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255,
					     255 };
   localparam int META1_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META2_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META3_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META4_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META5_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META6_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;
   localparam int META7_INDICES_DUMMY[0:21] = META0_INDICES_DUMMY;

   localparam int LEFT_ADDERS_DUMMY[0:1][0:2] = '{
					'{ 0, 0, 0 },
					'{ 11, 11, 11 } 
					};
   localparam int RIGHT_ADDERS_DUMMY[0:1][0:2] = '{
					 '{ 0, 0, 0 },
					 '{ 12, 12, 12 }
					 };
   localparam int TOP_ADDERS_DUMMY[0:1][0:1] = '{
					   '{ 0, 0 },
					   '{ 0, 2 } };

   localparam int BEAM_INDICES_DUMMY [0:1][0:2] = '{ '{0, 0, 0 },
						     '{1, 1, 1 } };
   
   localparam int BEAM_LEFT_OFFSETS_DUMMY [0:1] = '{ 0,
					       0 };
   localparam int BEAM_RIGHT_OFFSETS_DUMMY [0:1] = '{ 0,
						0 };
   localparam int BEAM_TOP_OFFSETS_DUMMY [0:1] = '{ 0,
					      0 };

endpackage // pueo_dummy_beams

`endif
