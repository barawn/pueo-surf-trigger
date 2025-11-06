`ifndef PUEO_BEAMS_SV
`define PUEO_BEAMS_SV

// The 11/6 version of the beams ASSUMES THERE'S ALREADY A 1 CLOCK
// DELAY FOR CHANNELS OTHER THAN 0 AND 4.
//
// This means JUST IMAGINE SUBTRACTING 8 from the top antenna delays
// (making them negative).
//
// Note that adders 3 and 4 aren't adjusted because they don't
// have the top antennas included anyway.
package pueo_beams;
	localparam int NUM_BEAM = 48;

        // Sample store depth is now 3 because we sliced a clock
        // from the top antennas.
	localparam int SAMPLE_STORE_DEPTH = 3;

	localparam int LEFT_ADDER_LEN = 7;

	localparam int LEFT_STORE_DEPTH = 2;

	localparam int RIGHT_ADDER_LEN = 7;

	localparam int RIGHT_STORE_DEPTH = 2;

	localparam int TOP_ADDER_LEN = 5;

	localparam int TOP_STORE_DEPTH = 1;

	localparam int META0_INDICES [0:21] = '{
		18,
		19,
		20,
		25,
		26,
		27,
		32,
		33,
		34,
		46,
		47,
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


	localparam int META1_INDICES [0:21] = '{
		4,
		5,
		6,
		11,
		12,
		13,
		18,
		19,
		20,
		39,
		40,
		41,
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


	localparam int META2_INDICES [0:21] = '{
		17,
		18,
		19,
		24,
		25,
		26,
		31,
		32,
		33,
		45,
		46,
		47,
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


	localparam int META3_INDICES [0:21] = '{
		3,
		4,
		5,
		10,
		11,
		12,
		17,
		18,
		19,
		38,
		39,
		40,
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


	localparam int META4_INDICES [0:21] = '{
		15,
		16,
		17,
		22,
		23,
		24,
		29,
		30,
		31,
		43,
		44,
		45,
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


	localparam int META5_INDICES [0:21] = '{
		1,
		2,
		3,
		8,
		9,
		10,
		15,
		16,
		17,
		36,
		37,
		38,
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


	localparam int META6_INDICES [0:21] = '{
		14,
		15,
		16,
		21,
		22,
		23,
		28,
		29,
		30,
		42,
		43,
		44,
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


	localparam int META7_INDICES [0:21] = '{
		0,
		1,
		2,
		7,
		8,
		9,
		14,
		15,
		16,
		35,
		36,
		37,
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

        // Except for 3 and 4 these have 8 subtracted from them
        // compared to the previous beams.
	localparam int LEFT_ADDERS [0:6][0:2] = '{
		'{ 11,13,15 },
		'{ 1,1,1 },
		'{ 9,10,11 },
		'{ 1,0,0 },
		'{ 0,2,5 },
		'{ 5,6,7 },
		'{ 3,3,4 } };


	localparam int RIGHT_ADDERS [0:6][0:2] = '{
		'{ 8,10,12 },
		'{ 2,2,2 },
		'{ 7,8,10 },
		'{ 1,0,0 },
		'{ 0,2,5 },
		'{ 6,7,8 },
		'{ 4,4,5 } };


	localparam int TOP_ADDERS [0:4][0:1] = '{
		'{ 0,1 },
		'{ 0,0 },
		'{ 2,0 },
		'{ 0,2 },
		'{ 1,0 } };


	localparam int BEAM_INDICES [0:47][0:2] = '{
		'{ 1,1,3 },
		'{ 1,1,3 },
		'{ 1,1,0 },
		'{ 1,1,0 },
		'{ 1,1,0 },
		'{ 1,1,1 },
		'{ 1,1,1 },
		'{ 6,6,3 },
		'{ 6,6,3 },
		'{ 6,6,0 },
		'{ 6,6,1 },
		'{ 6,6,1 },
		'{ 6,6,4 },
		'{ 6,6,4 },
		'{ 5,5,3 },
		'{ 5,5,0 },
		'{ 5,5,0 },
		'{ 5,5,1 },
		'{ 5,5,1 },
		'{ 5,5,4 },
		'{ 5,5,4 },
		'{ 2,2,3 },
		'{ 2,2,0 },
		'{ 2,2,1 },
		'{ 2,2,1 },
		'{ 2,2,4 },
		'{ 2,2,4 },
		'{ 2,2,2 },
		'{ 0,0,0 },
		'{ 0,0,1 },
		'{ 0,0,1 },
		'{ 0,0,4 },
		'{ 0,0,4 },
		'{ 0,0,2 },
		'{ 0,0,2 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 3,3,255 },
		'{ 4,4,255 },
		'{ 4,4,255 },
		'{ 4,4,255 },
		'{ 4,4,255 },
		'{ 4,4,255 },
		'{ 4,4,255 } };


	localparam int BEAM_LEFT_OFFSETS [0:47] = '{
		4,
		5,
		4,
		3,
		3,
		2,
		0,
		4,
		4,
		4,
		3,
		3,
		2,
		0,
		4,
		3,
		4,
		3,
		3,
		2,
		0,
		1,
		2,
		2,
		1,
		2,
		1,
		0,
		0,
		1,
		1,
		1,
		1,
		1,
		0,
		3,
		2,
		1,
		0,
		0,
		0,
		0,
		3,
		2,
		1,
		0,
		0,
		0 };


	localparam int BEAM_RIGHT_OFFSETS [0:47] = '{
		0,
		2,
		2,
		2,
		3,
		3,
		2,
		0,
		1,
		2,
		2,
		3,
		3,
		2,
		0,
		0,
		2,
		2,
		3,
		3,
		2,
		0,
		2,
		3,
		3,
		5,
		5,
		5,
		0,
		2,
		3,
		4,
		5,
		6,
		6,
		0,
		0,
		0,
		0,
		1,
		2,
		3,
		0,
		0,
		0,
		0,
		1,
		2 };


	localparam int BEAM_TOP_OFFSETS [0:47] = '{
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0 };


endpackage

`endif
