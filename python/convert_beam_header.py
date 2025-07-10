import argparse

def convert_beams_to_verilog(infilename = "L1Beams.csv", outfilename = "L1Beams_header.vh", lead_antennas = [0,4]):
    with open(infilename, "r") as infile:
        with open(outfilename, "w") as outfile:
            antenna_maxes = {}
            for antenna_idx in range(8):
                antenna_maxes[antenna_idx] = 0
            headerline = next(infile) # Might use in future version
            for beam_idx, line in enumerate(infile):
                line = line.strip().split(",")
                try:
                    elevation = float(line[0])
                    azimuth = float(line[1])
                except Exception as ValueError:
                    break
                delays = []
                for antenna_idx in range(8):
                    delay = int(line[antenna_idx+2])
                    if antenna_maxes[antenna_idx] < delay:
                        antenna_maxes[antenna_idx] = delay
                    outfile.write("`define BEAM_{:d}_ANTENNA_DELAY_{:d} {:d}\n".format(beam_idx, antenna_idx, delay))
                    # outfile.write("`define ")
            for antenna_idx in lead_antennas:
                outfile.write("`define MAX_ANTENNA_DELAY_{:d} {:d}\n".format(antenna_idx, antenna_maxes[antenna_idx]))
            print("Wrote out {:d} beams to \"{:s}\"".format(beam_idx-1, outfilename))

def convert_beams_to_verilog_arrays(infilename = "L1Beams.csv", outfilename = "L1Beams_header.vh", lead_antennas = None):
    with open(infilename, "r") as infile:
        with open(outfilename, "w") as outfile:
            antenna_maxes = {}
            for antenna_idx in range(8):
                antenna_maxes[antenna_idx] = 0
            headerline = next(infile) # Might use in future version
            outfile.write("`define BEAM_ANTENNA_DELAYS '{ \\")
            first=True
            for beam_idx, line in enumerate(infile):
                line = line.strip().split(",")
                try:
                    elevation = float(line[0])
                    azimuth = float(line[1])
                except Exception as ValueError:
                    break
                # Making it here means there is data
                if(not first):
                   outfile.write(", \\")
                else:
                    # outfile.write(", \\ // Beam %s"%beam_idx)
                    first = False
                delays = []
                outfile.write("\n\t'{")
                for antenna_idx in range(8):
                    delay = int(line[antenna_idx+2])
                    if antenna_maxes[antenna_idx] < delay:
                        antenna_maxes[antenna_idx] = delay
                    outfile.write("{:d}".format(delay))
                    if(antenna_idx != 7):
                        outfile.write(",")
                    # outfile.write(" ")
                outfile.write("}")
            outfile.write(" \\\n}\n")
            outfile.write("`define BEAM_TOTAL {:d}\n".format(beam_idx))
            if not lead_antennas is None:
                for antenna_idx in lead_antennas:
                    outfile.write("`define MAX_ANTENNA_DELAY_{:d} {:d}\n".format(antenna_idx, antenna_maxes[antenna_idx]))
            else:
                 for antenna_idx in range(8):
                    outfile.write("`define MAX_ANTENNA_DELAY_{:d} {:d}\n".format(antenna_idx, antenna_maxes[antenna_idx]))
            print("Wrote out {:d} beams to \"{:s}\"".format(beam_idx, outfilename))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert beam CSV to Verilog header.")
    parser.add_argument("infile", help="Input CSV filename")
    parser.add_argument("outfile", help="Output Verilog header filename")
    args = parser.parse_args()

    convert_beams_to_verilog_arrays(args.infile, args.outfile)