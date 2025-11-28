import numpy as np
from scipy import signal
from IIRSim_v2 import iir_biquad_coeffs

if __name__ == "__main__":
    #q_factor=5
    samp_per_clock=4
    if(False): # Loop
        for q_factor in range(1,19):
            print(f"Q factor: {q_factor}\t, Samples Per Clock: {samp_per_clock}")
            for notch_freq in range(200,749,10):
                b, a = signal.iirnotch(notch_freq, q_factor, 3000/(8/samp_per_clock)) # The natural RFSoC grouping is 8
                # First generate the coefficients for the FPGA Biquad
                pole = signal.tf2zpk(b,a)[1][0]
                zero = signal.tf2zpk(b,a)[0][0]
                mag=np.abs(pole)
                angle=np.angle(pole)
                coeffs = iir_biquad_coeffs(mag, angle, samp_per_clock=4)
                coeffs_fixed_point = np.zeros(len(coeffs), dtype=np.int64)
                coeffs_fixed_point_signed = np.zeros(len(coeffs), dtype=np.int64)
                b_fixed_point_signed = np.zeros(len(b))
                # For transfer function numerator
                for i in range(len(b)):
                    b_fixed_point_signed[i] = np.array(np.floor(b[i] * (2**14)),dtype=np.int64)
                a_fixed_point_signed = np.zeros(len(a))
                # For transfer function denominator, after look-ahead
                for i in range(len(a)):
                    a_fixed_point_signed[i] = np.array(np.floor(a[i] * (2**14)),dtype=np.int64)
                # For clustered look-ahead
                for i in range(len(coeffs_fixed_point)):
                    # Coefficients are in Q4.14, where the sign bit IS counted
                    # print(f"Coeff {i}: {coeffs[i]}")
                    coeffs_fixed_point_signed[i] = np.array(np.floor(coeffs[i] * (2**14)),dtype=np.int64)
                    
                    # print(f"\tCoeff {i}: 0x{coeffs_fixed_point_signed[i]:X}, {coeffs_fixed_point_signed[i]}")
                    # coeffs_fixed_point[i] = convert_to_fixed_point(np.array(coeffs[i]), 4, 14)
                f_fir = coeffs_fixed_point_signed[0:samp_per_clock-2]
                g_fir = coeffs_fixed_point_signed[samp_per_clock-2:2*samp_per_clock-3]
                D_FF = coeffs_fixed_point_signed[2*samp_per_clock-3 + 0]
                D_FG = coeffs_fixed_point_signed[2*samp_per_clock-3 + 1]
                E_GF = coeffs_fixed_point_signed[2*samp_per_clock-3 + 2]
                E_GG = coeffs_fixed_point_signed[2*samp_per_clock-3 + 3]
                C = coeffs_fixed_point_signed[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4]
                
                if(samp_per_clock == 8):
                    with open("freq_files/coeff_file_%sMHz_%sQ.dat"%(notch_freq,q_factor),"w") as coeff_file:
                        coeff_file.write("%d\n"%(int(b_fixed_point_signed[1])))# B
                        coeff_file.write("%d\n"%(int(b_fixed_point_signed[0])))# A

                        coeff_file.write("%d\n"%(int(C[2])))# C2
                        coeff_file.write("%d\n"%(int(C[3])))# C3
                        coeff_file.write("%d\n"%(int(C[1])))# C1
                        coeff_file.write("%d\n"%(int(C[0])))# C0

                        coeff_file.write("%d\n"%(int(a_fixed_point_signed[2])))# a2'
                        coeff_file.write("%d\n"%(int(a_fixed_point_signed[1])))# a1'        

                        coeff_file.write("%d\n"%(int(D_FF)))# D_FF
                        coeff_file.write("%d\n"%(int(f_fir[5])))# X6
                        coeff_file.write("%d\n"%(int(f_fir[4])))# X5
                        coeff_file.write("%d\n"%(int(f_fir[3])))# X4
                        coeff_file.write("%d\n"%(int(f_fir[2])))# X3
                        coeff_file.write("%d\n"%(int(f_fir[1])))# X2
                        coeff_file.write("%d\n"%(int(f_fir[0])))# X1

                        coeff_file.write("%d\n"%(int(E_GG)))# E_GG
                        coeff_file.write("%d\n"%(int(g_fir[6])))# X7
                        coeff_file.write("%d\n"%(int(g_fir[5])))# X6
                        coeff_file.write("%d\n"%(int(g_fir[4])))# X5
                        coeff_file.write("%d\n"%(int(g_fir[3])))# X4
                        coeff_file.write("%d\n"%(int(g_fir[2])))# X3
                        coeff_file.write("%d\n"%(int(g_fir[1])))# X2
                        coeff_file.write("%d\n"%(int(g_fir[0])))# X1
                        
                        coeff_file.write("%d\n"%(int(D_FG)))# D_FG
                        
                        coeff_file.write("%d\n"%(int(E_GF)))# E_GF

                        for a_i in a_fixed_point_signed:
                            coeff_file.write("%d\n"%(int(a_i)))
                        for b_i in b_fixed_point_signed:
                            coeff_file.write("%d\n"%(int(b_i)))
                elif(samp_per_clock == 4):
                    with open("freq_files/coeff_4sample_file_%sMHz_%sQ.dat"%(notch_freq,q_factor),"w") as coeff_file:
                        coeff_file.write("%d\n"%(int(b_fixed_point_signed[1])))# B
                        coeff_file.write("%d\n"%(int(b_fixed_point_signed[0])))# A

                        coeff_file.write("%d\n"%(int(C[2])))# C2
                        coeff_file.write("%d\n"%(int(C[3])))# C3
                        coeff_file.write("%d\n"%(int(C[1])))# C1
                        coeff_file.write("%d\n"%(int(C[0])))# C0

                        coeff_file.write("%d\n"%(int(a_fixed_point_signed[2])))# a2'
                        coeff_file.write("%d\n"%(int(a_fixed_point_signed[1])))# a1'        

                        coeff_file.write("%d\n"%(int(D_FF)))# D_FF
                        coeff_file.write("%d\n"%(int(f_fir[1])))# X2
                        coeff_file.write("%d\n"%(int(f_fir[0])))# X1

                        coeff_file.write("%d\n"%(int(E_GG)))# E_GG
                        coeff_file.write("%d\n"%(int(g_fir[2])))# X3
                        coeff_file.write("%d\n"%(int(g_fir[1])))# X2
                        coeff_file.write("%d\n"%(int(g_fir[0])))# X1
                        
                        coeff_file.write("%d\n"%(int(D_FG)))# D_FG
                        
                        coeff_file.write("%d\n"%(int(E_GF)))# E_GF

                        for a_i in a_fixed_point_signed:
                            coeff_file.write("%d\n"%(int(a_i)))
                        for b_i in b_fixed_point_signed:
                            coeff_file.write("%d\n"%(int(b_i)))
    else:
        print(f"Writing out single 4th order notch ")
        sos = signal.cheby2(N=4, rs=20, Wn=[355.0, 385.0], analog=False, btype='bandstop', output='sos', fs=1500)
        a_s = [sos[0][3:5], sos[1][3:5]]
        b_s = [sos[0][0:2], sos[1][0:2]]
        filename = "FourthOrder"
        # b, a = signal.iirnotch(notch_freq, q_factor, 3000/(8/samp_per_clock)) # The natural RFSoC grouping is 8
        # b = [1.00000000, 0.04211555, 1.00000000]#[0.70538294, 0.02970759 , 0.70538294]
        #a = [1.00000000, 0.25804049, 0.78158487]#[1.00000000, -0.18405882, 0.78056541]
        # First generate the coefficients for the FPGA Biquad
        for idx in range(2):
            a = a_s[idx]
            b = b_s[idx]
            pole = signal.tf2zpk(b,a)[1][0]
            zero = signal.tf2zpk(b,a)[0][0]
            mag=np.abs(pole)
            angle=np.angle(pole)
            print(f"Mag:{mag}, Angle:{angle*180/3.1415926}")
            coeffs = iir_biquad_coeffs(mag, angle, samp_per_clock=4)
            coeffs_fixed_point = np.zeros(len(coeffs), dtype=np.int64)
            coeffs_fixed_point_signed = np.zeros(len(coeffs), dtype=np.int64)
            b_fixed_point_signed = np.zeros(len(b))
            # For transfer function numerator
            for i in range(len(b)):
                b_fixed_point_signed[i] = np.array(np.floor(b[i] * (2**14)),dtype=np.int64)
            a_fixed_point_signed = np.zeros(len(a))
            # For transfer function denominator, after look-ahead
            for i in range(len(a)):
                a_fixed_point_signed[i] = np.array(np.floor(a[i] * (2**14)),dtype=np.int64)
            # For clustered look-ahead
            for i in range(len(coeffs_fixed_point)):
                # Coefficients are in Q4.14, where the sign bit IS counted
                # print(f"Coeff {i}: {coeffs[i]}")
                coeffs_fixed_point_signed[i] = np.array(np.floor(coeffs[i] * (2**14)),dtype=np.int64)
                
                # print(f"\tCoeff {i}: 0x{coeffs_fixed_point_signed[i]:X}, {coeffs_fixed_point_signed[i]}")
                # coeffs_fixed_point[i] = convert_to_fixed_point(np.array(coeffs[i]), 4, 14)
            f_fir = coeffs_fixed_point_signed[0:samp_per_clock-2]
            g_fir = coeffs_fixed_point_signed[samp_per_clock-2:2*samp_per_clock-3]
            D_FF = coeffs_fixed_point_signed[2*samp_per_clock-3 + 0]
            D_FG = coeffs_fixed_point_signed[2*samp_per_clock-3 + 1]
            E_GF = coeffs_fixed_point_signed[2*samp_per_clock-3 + 2]
            E_GG = coeffs_fixed_point_signed[2*samp_per_clock-3 + 3]
            C = coeffs_fixed_point_signed[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4]
            
            if(samp_per_clock == 8):
                with open("freq_files/coeff_file_%sMHz_%sQ.dat"%(notch_freq,q_factor),"w") as coeff_file:
                    coeff_file.write("%d\n"%(int(b_fixed_point_signed[1])))# B
                    coeff_file.write("%d\n"%(int(b_fixed_point_signed[0])))# A

                    coeff_file.write("%d\n"%(int(C[2])))# C2
                    coeff_file.write("%d\n"%(int(C[3])))# C3
                    coeff_file.write("%d\n"%(int(C[1])))# C1
                    coeff_file.write("%d\n"%(int(C[0])))# C0

                    coeff_file.write("%d\n"%(int(a_fixed_point_signed[2])))# a2'
                    coeff_file.write("%d\n"%(int(a_fixed_point_signed[1])))# a1'        

                    coeff_file.write("%d\n"%(int(D_FF)))# D_FF
                    coeff_file.write("%d\n"%(int(f_fir[5])))# X6
                    coeff_file.write("%d\n"%(int(f_fir[4])))# X5
                    coeff_file.write("%d\n"%(int(f_fir[3])))# X4
                    coeff_file.write("%d\n"%(int(f_fir[2])))# X3
                    coeff_file.write("%d\n"%(int(f_fir[1])))# X2
                    coeff_file.write("%d\n"%(int(f_fir[0])))# X1

                    coeff_file.write("%d\n"%(int(E_GG)))# E_GG
                    coeff_file.write("%d\n"%(int(g_fir[6])))# X7
                    coeff_file.write("%d\n"%(int(g_fir[5])))# X6
                    coeff_file.write("%d\n"%(int(g_fir[4])))# X5
                    coeff_file.write("%d\n"%(int(g_fir[3])))# X4
                    coeff_file.write("%d\n"%(int(g_fir[2])))# X3
                    coeff_file.write("%d\n"%(int(g_fir[1])))# X2
                    coeff_file.write("%d\n"%(int(g_fir[0])))# X1
                    
                    coeff_file.write("%d\n"%(int(D_FG)))# D_FG
                    
                    coeff_file.write("%d\n"%(int(E_GF)))# E_GF

                    for a_i in a_fixed_point_signed:
                        coeff_file.write("%d\n"%(int(a_i)))
                    for b_i in b_fixed_point_signed:
                        coeff_file.write("%d\n"%(int(b_i)))
            elif(samp_per_clock == 4):
                with open(f"{filename}_0.dat","w") as coeff_file:
                    coeff_file.write("%d\n"%(int(b_fixed_point_signed[1])))# B
                    coeff_file.write("%d\n"%(int(b_fixed_point_signed[0])))# A

                    coeff_file.write("%d\n"%(int(C[2])))# C2
                    coeff_file.write("%d\n"%(int(C[3])))# C3
                    coeff_file.write("%d\n"%(int(C[1])))# C1
                    coeff_file.write("%d\n"%(int(C[0])))# C0

                    coeff_file.write("%d\n"%(int(a_fixed_point_signed[2])))# a2'
                    coeff_file.write("%d\n"%(int(a_fixed_point_signed[1])))# a1'        

                    coeff_file.write("%d\n"%(int(D_FF)))# D_FF
                    coeff_file.write("%d\n"%(int(f_fir[1])))# X2
                    coeff_file.write("%d\n"%(int(f_fir[0])))# X1

                    coeff_file.write("%d\n"%(int(E_GG)))# E_GG
                    coeff_file.write("%d\n"%(int(g_fir[2])))# X3
                    coeff_file.write("%d\n"%(int(g_fir[1])))# X2
                    coeff_file.write("%d\n"%(int(g_fir[0])))# X1
                    
                    coeff_file.write("%d\n"%(int(D_FG)))# D_FG
                    
                    coeff_file.write("%d\n"%(int(E_GF)))# E_GF

                    for a_i in a_fixed_point_signed:
                        coeff_file.write("%d\n"%(int(a_i)))
                    for b_i in b_fixed_point_signed:
                        coeff_file.write("%d\n"%(int(b_i)))