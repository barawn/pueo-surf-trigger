import numpy as np
from matplotlib import pyplot as plt
from scipy.signal import lfilter
from scipy import signal
import scipy
import math
from scipy.special import eval_chebyu


def import_data_dep(file_loc, truncate=True, debug = False):
    captured_data = np.load(file_loc)
    input0_offset=np.argmax((np.abs(captured_data[0])>0).astype(int))
    input1_offset=np.argmax((np.abs(captured_data[1])>0).astype(int))
    output0_offset=np.argmax((np.abs(captured_data[2])>0).astype(int))
    output1_offset=np.argmax((np.abs(captured_data[3])>0).astype(int))
    
    # Truncate to 12 bits from 16, data was originally 12 and MSB aligned in 16
    input0 = captured_data[0]
    input1 = captured_data[1]
    if(truncate):
        input0 = np.right_shift(input0,4).astype(np.int16)
        input1 = np.right_shift(input1,4).astype(np.int16)
        output0 = np.right_shift(captured_data[2],4).astype(np.int16)
        output1 = np.right_shift(captured_data[3],4).astype(np.int16)

    # output0 = captured_data[2]
    # output1 = captured_data[3]

    if(debug):
        print("input0_offset: %s"%(input0_offset))
        print("input1_offset: %s"%(input1_offset))
        print("output0_offset: %s"%(output0_offset))
        print("output1_offset: %s"%(output1_offset))

        print("input0_offset%%8: %s"%(input0_offset%8))
        print("input1_offset%%8: %s"%(input1_offset%8))
        print("output0_offset%%8: %s"%(output0_offset%8))
        print("output1_offset%%8: %s"%(output1_offset%8))

        print("input 0 first value: %s"%input0[input0_offset])
        print("input 1 first value: %s"%input1[input1_offset])
    
    return (input0, input1, output0, output1, input0_offset, input1_offset, output0_offset, output1_offset)



def bindigits(n, bits):
    """ https://stackoverflow.com/questions/12946116/twos-complement-binary-in-python
    Takes an integer value and number of bits, and converts to two's complement string
    Basically just masks off the number of bits. Python twos-complement are infinite length (...111111111101, for example)
    """
    s = bin(n & int("1"*bits, 2))[2:] # The [2:] cuts off the 0b of 0b######
    return ("{0:0>%s}" % (bits)).format(s)

def twos_complement_integer(n, bits):
    """ Returns two's complement representation of n as a <bits> bit number
    """
    return int(bindigits(n,bits),2)

def convert_to_fixed_point(a, a_int, a_frac, allow_overflow=False):
    """Converts to an integer with <a_frac> bits of of fractional representation, and <a_int> bits of integer
    i.e. Q<a_int>.<a_frac> (ARM)
    """
    if((a>=(2**(max(a_int-1,0))) or a<-1*(2**(max(a_int-1,0)))) and not allow_overflow):
        raise Exception("Value %s out of bounds"%a)
    # Multiply fractional bits up to integers
    # Removing digits of a twos complement goes more negative, so we mimic that in advance
    a_temp = math.floor(a * (2**a_frac))

    if (a<0):
        # Convert to twos complement
        # print("Converting to twos complement")
        # print("%s = %s"%(a_temp, bin(a_temp)))
        a_temp = twos_complement_integer(a_temp, a_int+a_frac)
        # print("%s = %s"%(a_temp, bin(a_temp)))
        # print(bin(a_temp))
    a_temp = a_temp & int("1"*(a_int+a_frac), 2)
    return a_temp

def convert_from_fixed_point(a, a_int, a_frac, twos_complement=True):
    """Converts from a signed integer (Q<a_int>.<a_frac>, ARM) representation to a floating point
    """
    if(a<0):
        raise Exception("Expecting a to be respresented as an unsigned number")
    bits = a_int + a_frac
    
    if(twos_complement):
        if(a>=2**(bits+1)):
                raise Exception("Value %s out of bounds. Bits available: %s"%(a,bits+1))
        # If it is signed
        if (a & (1<<(bits-1))):
            # print("Signed")
            a = (-1*(1<<(bits)) + a)
    else:
        if(a>=(2**(bits)) or a<-1*(2**(bits))):
            raise Exception("Value %s out of bounds"%a)
    a_temp = (a / (2.0**a_frac))#%(2**a_int)
    
    return a_temp

def multiply_dep(a, b, a_int, a_frac, b_int, b_frac, out_int, out_frac):
    """ We are assuming that the fixed point limits of the inputs are already followed.
    This means that normal multiplication is allowed if no error is thrown."""
    a = convert_to_fixed_point(a, a_int, a_frac)
    b = convert_to_fixed_point(b, b_int, b_frac)
    result_int = a * b # Not sure this treats negatives right
    return convert_from_fixed_point(result_int, out_int, out_frac, twos_complement=False)
    
def manual_fir_section_convert(coeffs, x, coeff_int, coeff_frac, data_int, data_frac, out_int=22, out_frac=26):
    for coeff_set in coeffs:
        for c in coeff_set:
            if(c >= 2**18 or c < -1*(2**18)):
                raise Exception("Coefficient out of bounds")
    
    x = np.array(x)
    y = np.zeros(len(x))
    for coeff_set in coeffs:
        for i in range(len(coeff_set), len(x)):
            total = 0
            for j in range(len(coeff_set)):
                c = convert_to_fixed_point(coeff_set[j], coeff_int, coeff_frac)
                x_point = convert_to_fixed_point(x[i-j], data_int, data_frac)
                total += c * x_point
            # get actual value after fixed point math
            y[i] = convert_from_fixed_point(total, coeff_int + data_int, coeff_frac+data_frac)
            # Reduce to precision of output. In the firmware overflow is clipped off
            val = convert_to_fixed_point(y[i], out_int, out_frac, allow_overflow=True)
            y[i] = convert_from_fixed_point(val, out_int, out_frac)
#             if(total>0):
#                 print(total)
#                 print(y[i])
        x=np.copy(y)
        y=np.zeros(len(x))
    return x

def get_f_coeffs(samp_per_clock, mag, angle): # CHANGED 2/17
    f_fir = [0]*(samp_per_clock-2)
    for i in range(0, samp_per_clock-2):
        f_fir[i] = pow(mag, i+1)*eval_chebyu(i+1,np.cos(angle) )
    return f_fir

def get_g_coeffs(samp_per_clock, mag, angle): # CHANGED 2/17
    g_fir = [0]*(samp_per_clock-1)
    for i in range(0, samp_per_clock-1):
        g_fir[i] = pow(mag, i+1)*eval_chebyu(i+1,np.cos(angle) )
    return g_fir

def get_F_G_coefficients(samp_per_clock, mag, angle):
    D_FF = -1*pow(mag, samp_per_clock)*eval_chebyu(samp_per_clock-2, np.cos(angle)) #L -alpha
    E_GG =  pow(mag, samp_per_clock)*eval_chebyu(samp_per_clock, np.cos(angle)) #L delta

    # Crosslink coefficients. 
    D_FG = pow(mag, samp_per_clock-1)*eval_chebyu(samp_per_clock-1, np.cos(angle))#L beta
    # Lucas note - This was changed to add a negative sign, better matching the paper
    E_GF = -1*pow(mag, samp_per_clock+1)*eval_chebyu(samp_per_clock-1, np.cos(angle))#L -gamma
    return np.array([D_FF, D_FG, E_GF, E_GG])

# Adapted from https://github.com/barawn/pueo-dsp-python/tree/main/dsp. It is not tracked because I don't want to set up a submodule right now
def iir_biquad_coeffs(mag, angle, zero_angle=None, samp_per_clock=8):
    # Calculate the f and g fir coefficients, using the angle of the notch, the samples
    f_fir = get_f_coeffs(samp_per_clock, mag, angle)
    g_fir = get_g_coeffs(samp_per_clock, mag, angle)

    # Now we need to compute the F and G functions, which *again* are just FIRs,
    # however they're cross-linked, so it's a little trickier.
    # We split it into
    # F = (fir on f) + G_coeff*g(previous clock)
    # G = (fir on g) + F_coeff*f(previous clock)

    D_FF, D_FG, E_GF, E_GG = get_F_G_coefficients(samp_per_clock, mag, angle)

    # IIR parameters. See the 'update step' in paper.
    C = np.zeros(4)
    C[0] = pow(mag, 2*samp_per_clock)*(pow(eval_chebyu(samp_per_clock-2, np.cos(angle)), 2) -
                                       pow(eval_chebyu(samp_per_clock-1, np.cos(angle)), 2))

    C[1] = pow(mag, 2*samp_per_clock-1)*((eval_chebyu(samp_per_clock-1, np.cos(angle)))*
                                         (eval_chebyu(samp_per_clock,np.cos(angle)) -
                                          eval_chebyu(samp_per_clock-2, np.cos(angle))))

    C[2] = pow(mag, 2*samp_per_clock+1)*((eval_chebyu(samp_per_clock-1, np.cos(angle)))*
                                         (eval_chebyu(samp_per_clock-2, np.cos(angle))-
                                          eval_chebyu(samp_per_clock, np.cos(angle))))

    C[3] = pow(mag, 2*samp_per_clock)*(pow(eval_chebyu(samp_per_clock, np.cos(angle)), 2) -
                                       pow(eval_chebyu(samp_per_clock-1, np.cos(angle)), 2))

    coeffs = np.zeros(2*samp_per_clock-3 + 4 + 4)
    coeffs[0:samp_per_clock-2] = np.array(f_fir)
    coeffs[samp_per_clock-2:2*samp_per_clock-3] = np.array(g_fir)
    coeffs[2*samp_per_clock-3:2*samp_per_clock-3 + 4] = get_F_G_coefficients(samp_per_clock, mag, angle)
    coeffs[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4] = C
    
    return coeffs

def iir_biquad_run(ins, coeffs, samp_per_clock=8, ics=None, manual_filter=False, decimate=True, mag=0, angle=0, fixed_point=False, debug=0):
    if ics is None:
        # Debugging
        if debug>1:
            print("No initial conditions!")
        ics = np.zeros(samp_per_clock*3)
        ics = ics.reshape(3,-1)
    ins = np.array(ins, dtype=np.int64)
    coeffs = np.array(coeffs, dtype=np.int64)
    # Expand the inputs with the initial conditions
    newins = np.concatenate( (ics[0],ins) )

    f_fir = coeffs[0:samp_per_clock-2]
    g_fir = coeffs[samp_per_clock-2:2*samp_per_clock-3]
    D_FF = coeffs[2*samp_per_clock-3 + 0]
    D_FG = coeffs[2*samp_per_clock-3 + 1]
    E_GF = coeffs[2*samp_per_clock-3 + 2]
    E_GG = coeffs[2*samp_per_clock-3 + 3]
    C = coeffs[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4]
    # print(C.dtype)
    # Run the FIRs
    if(manual_filter):
        raise Exception("Not implemented yet")
    else:
        f = signal.lfilter( f_fir, [1], newins )
        g = signal.lfilter( g_fir, [1], newins )
        # Now we decimate f/g by 8, because we only want the 0th and 1st samples out of 8 for each.
    
    f = f.reshape(-1, samp_per_clock).transpose()[0]
    g = g.reshape(-1, samp_per_clock).transpose()[1]
    
    # n.b. f[0]/g[0] are initial conditions

    # Lucas note: I think this should be f[1] and g[1]
    # f[2] (real sample 8) is calculated from 8, 7, 6, 5, 4, 3, 2.
    # g[2] (real sample 9) is calculated from 9, 8, 7, 6, 5, 4, 3, 2.

    # Now we need to compute the F and G functions, which *again* are just FIRs,
    # however they're cross-linked, so it's a little trickier.
    # We split it into
    # F = (fir on f) + G_coeff*g(previous clock)
    # G = (fir on g) + F_coeff*f(previous clock)
    
    F_fir = [ 1.0, D_FF ] # This is for sample 0
    G_fir = [ 1.0, E_GG ] # This is for sample 1

    # Debugging
    if debug>1:
        print("F/G FIRs operate on f/g inputs respectively")
        print("D_FF:", D_FF, " D_FG:", D_FG)
        print("E_GG:", E_GG, " E_GF:", E_GF)
        print()
    
    # print("F/G FIRs operate on f/g inputs respectively")
    # print("F FIR:", F_fir, "+g*", D_FG)
    # print("G FIR:", G_fir, "-f*", E_GF)
    # print()
    # print("As full FIRs calculated only for sample 0 and 1 respectively:")
    # print("F = f + (fz^-", samp_per_clock, ")+",Coeff_g_in_F,"*(gz^-", samp_per_clock-1, ")",sep='')
    # print("G = g + (gz^-", samp_per_clock, ")+",Coeff_f_in_G,"*(fz^-", samp_per_clock+1, ")",sep='')
        
    # Filter them
    F = signal.lfilter( F_fir, [1], f )
    G = signal.lfilter( G_fir, [1], g )

    # Now we need to feed the f/g paths into the opposite filter
    # F[0]/G[0] are going to be dropped anyway.
    F[1:] += D_FG*g[0:-1]
    G[1:] += E_GF*f[0:-1]    

    # drop the initial conditions
    F = F[1:]
    G = G[1:]
    
    # Now reshape our outputs.
    arr = np.array(ins.reshape(-1, samp_per_clock).transpose(), dtype=np.int64)
    # arr[0] is now every 0th sample (e.g. for samp_per_clock = 8, it's 0, 8, 16, 24, etc.)
    # arr[1] is now every 1st sample (e.g. for samp_per_clock = 8, it's 1, 9, 17, 25, etc.)
    # Debugging
    if debug>1:
        print("Update step (matrix) coefficients:", C)
        print("As an IIR: (Lucas thinks there is a typo here)")
        print("y[0] =", C[1], "*z^-", samp_per_clock*2-1," + ", C[0], "*z^-", samp_per_clock*2,
              "+F[0]",sep='')
        print("y[1] =", C[3], "*z^-", samp_per_clock*2," + ", C[2], "*z^-", samp_per_clock*2+1,
              "+G[1]",sep='')
    # Now compute the IIR.
    # INITIAL CONDITIONS STEP
    y0_0 =  C[0]*ics[1][0] + C[1]*ics[1][1] + F[0]
    y1_0 =  C[2]*ics[1][0] + C[3]*ics[1][1] + G[0]
    y0_1 =  C[0]*ics[2][0] + C[1]*ics[2][1] + F[1]
    y1_1 =  C[2]*ics[2][0] + C[3]*ics[2][1] + G[1]
    for i in range(len(arr[0])):
        if i == 0:
            # Compute from initial conditions.
            arr[0][i] = C[0]*y0_0 + C[1]*y1_0 + F[i]
            arr[1][i] = C[2]*y0_0 + C[3]*y1_0 + G[i]
        elif i==1:
            # Compute from initial conditions
            arr[0][i] = C[0]*y0_1 + C[1]*y1_1 + F[i]
            arr[1][i] = C[2]*y0_1 + C[3]*y1_1 + G[i]
        else:
            # THIS IS THE ONLY RECURSIVE STEP
            arr[0][i] = C[0]*arr[0][i-2] + C[1]*arr[1][i-2] + F[i]
            arr[1][i] = C[2]*arr[0][i-2] + C[3]*arr[1][i-2] + G[i]
            if(arr[0][i-2]>0):
                if (debug>0):
                    print("\n********")
                    print("C[0]: %s"%C[0])
                    print("arr[0][i-2]: %s"%arr[0][i-2])
                    print("arr[0][i]: %s"%arr[0][i])
                    print("********")
                    print("C[1]: %s"%C[1])
                    print("arr[1][i-2]: %s"%arr[1][i-2])
                    print("arr[1][i]: %s"%arr[1][i])
                    print("********\n")
        # THIS IS NOT RECURSIVE B/C WE DO NOT TOUCH THE SECOND INDEX
        # print("DEBUG: I'm zero-ing samples 1-8")
        for j in range(2, samp_per_clock):
            if decimate:
                arr[j][i] = 0# DEBUG
            else:
                arr[j][i] += 2*mag*np.cos(angle)*arr[j-1][i] - pow(mag, 2)*arr[j-2][i]
    # print(arr)
    # now transpose arr and flatten
    output = arr.transpose().reshape(-1) 
    
    return output 


def iir_biquad_run_fixed_point(ins, coeffs, samp_per_clock=8, ics=None, manual_filter=False, decimate=True, a1=0, a2=0, fixed_point=False, debug=0):
    if ics is None:
        # Debugging
        if debug>1:
            print("No initial conditions!")
        ics = np.zeros(samp_per_clock*3)
        ics = ics.reshape(3,-1)
    ins = np.array(ins, dtype=np.int64)
    coeffs = np.array(coeffs, dtype=np.int64)
    # Expand the inputs with the initial conditions
    newins = np.concatenate( (ics[0],ins) )

    f_fir = coeffs[0:samp_per_clock-2]
    g_fir = coeffs[samp_per_clock-2:2*samp_per_clock-3]
    D_FF = coeffs[2*samp_per_clock-3 + 0]
    D_FG = coeffs[2*samp_per_clock-3 + 1]
    E_GF = coeffs[2*samp_per_clock-3 + 2]
    E_GG = coeffs[2*samp_per_clock-3 + 3]
    C = coeffs[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4]
    # print(C.dtype)

    
    if (debug>1):
        print("f fir: %s"%f_fir)
        print("g fir: %s"%g_fir)
        for i in range(len(newins)):
            if(newins[i] != 0):
                print("newins index %s: %s"%(i, newins[i]))
    
    # Run the FIRs
    if(manual_filter):
        raise Exception("Not implemented yet")
    else:
        f = signal.lfilter( f_fir, [1], newins )#/(2**14) # This will treat negatives wrong if you are using twos complement
        g = signal.lfilter( g_fir, [1], newins )#/(2**14)
        # Now we decimate f/g by 8, because we only want the 0th and 1st samples out of 8 for each.
    
    f = f.reshape(-1, samp_per_clock).transpose()[0]
    g = g.reshape(-1, samp_per_clock).transpose()[1]
    
    if (debug>1):
        print("HERE 2")
        for i in range(len(f)):
            if(f[i] != 0):
                print("f index %s: %s"%(i, f[i]))
        for i in range(len(g)):
            if(g[i] != 0):
                print("g index %s: %s"%(i, g[i]))
            # print("g index shifted %s: %s"%(i, g[i]/(2**14)))
    # n.b. f[0]/g[0] are initial conditions

    # f[2] (real sample 8) is calculated from 8, 7, 6, 5, 4, 3, 2.
    # g[2] (real sample 9) is calculated from 9, 8, 7, 6, 5, 4, 3, 2.

    # Now we need to compute the F and G functions, which *again* are just FIRs,
    # however they're cross-linked, so it's a little trickier.
    # We split it into
    # F = (fir on f) + G_coeff*g(previous clock)
    # G = (fir on g) + F_coeff*f(previous clock)
    
    F_fir = [ 2**14, D_FF ] # This is for sample 0 # WAS 2**14
    G_fir = [ 2**14, E_GG ] # This is for sample 1

    
    if (debug>1):
        # Debugging
        print("F/G FIRs operate on f/g inputs respectively")
        print("D_FF:", D_FF, " D_FG:", D_FG)
        print("E_GG:", E_GG, " E_GF:", E_GF)
        print()

    # Filter them
    F = signal.lfilter( F_fir, [1], f )#/(2**14) # The 14 bit shift will come later, with the lookbacks
    G = signal.lfilter( G_fir, [1], g )#/(2**14)

    # Now we need to feed the f/g paths into the opposite filter
    # F[0]/G[0] are going to be dropped anyway.
    F[1:] += D_FG*g[0:-1]#/(2**14)
    G[1:] += E_GF*f[0:-1]#/(2**14)    

    
    if (debug>1):
        print("HERE 3")
        for i in range(len(F)):
            if(F[i] != 0):
                print("F index %s: %s"%(i, F[i]))
        for i in range(len(G)):
            if(G[i] != 0):
                print("G index %s: %s"%(i, G[i]))
    
    # drop the initial conditions
    F = np.array(np.floor(F[1:]), dtype=np.int64)
    G = np.array(np.floor(G[1:]), dtype=np.int64)
    
    # Now reshape our outputs.
    arr = np.array(ins.reshape(-1, samp_per_clock).transpose(), dtype=np.int64)
    arr_intermediate = np.array(ins.reshape(-1, samp_per_clock).transpose(), dtype=np.int64)
    # arr[0] is now every 0th sample (e.g. for samp_per_clock = 8, it's 0, 8, 16, 24, etc.)
    # arr[1] is now every 1st sample (e.g. for samp_per_clock = 8, it's 1, 9, 17, 25, etc.)
    # Debugging
    
    if (debug>1):
        print("Update step (matrix) coefficients:", C)
        print("As an IIR: (Lucas thinks there is a typo here)")
        print("y[0] =", C[1], "*z^-", samp_per_clock*2-1," + ", C[0], "*z^-", samp_per_clock*2,
              "+F[0]",sep='')
        print("y[1] =", C[3], "*z^-", samp_per_clock*2," + ", C[2], "*z^-", samp_per_clock*2+1,
              "+G[1]",sep='')
    # Now compute the IIR.
    # INITIAL CONDITIONS STEP
    y0_0 =  C[0]*ics[1][0] + C[1]*ics[1][1] + F[0]
    y1_0 =  C[2]*ics[1][0] + C[3]*ics[1][1] + G[0]
    y0_1 =  C[0]*ics[2][0] + C[1]*ics[2][1] + F[1]
    y1_1 =  C[2]*ics[2][0] + C[3]*ics[2][1] + G[1]
    for i in range(len(arr[0])):
        if i == 0:
            # Compute from initial conditions.
            arr_intermediate[0][i] = np.int64(C[0]*y0_0 + C[1]*y1_0 + np.right_shift(F[i],1))
            arr_intermediate[1][i] = np.int64(C[2]*y0_0 + C[3]*y1_0 +np.right_shift(G[i],1))
        elif i==1:
            # Compute from initial conditions
            arr_intermediate[0][i] = np.int64(C[0]*y0_1 + C[1]*y1_1 + np.right_shift(F[i],1))
            arr_intermediate[1][i] = np.int64(C[2]*y0_1 + C[3]*y1_1 + np.right_shift(G[i],1))
        else:
            # THIS IS THE ONLY RECURSIVE STEP
            # FIRS come in in Q21.27, but were multiplied by Q
            # A regiter has 13 fractional bits
            # B register (Coefficient) has 14 fractional bits
            # C register (fir add) therefore has to be 27 to match, but was multiplied by Q4.14 coefficients twice.
            arr_intermediate[0][i] = np.int64(C[0]*np.right_shift(arr_intermediate[0][i-2],0)
                                                                  + C[1]*np.right_shift(arr_intermediate[1][i-2],0)
                                                                  + np.right_shift(F[i],1))
            #1 The A register (the feedback) has 13 Fractional bits. The FIRs went through 2 rounds of 14 fractional bit coeffs, and only had one removed
            arr_intermediate[1][i] = np.int64(C[2]*np.right_shift(arr_intermediate[0][i-2],0) 
                                                                  + C[3]*np.right_shift(arr_intermediate[1][i-2],0)
                                                                  + np.right_shift(G[i],1))
            
            if debug >=1 and (arr_intermediate[0][i] != 0 or arr_intermediate[1][i] != 0):
                print("Sample %d: F=%s, G=%s, arr_intermediate[0][i-2]=%s, arr_intermediate[1][i-2]=%s"%(i*8, 
                                                                                         F[i], 
                                                                                         G[i], 
                                                                                         arr_intermediate[0][i-2],
                                                                                         arr_intermediate[1][i-2]))
            # if(F[i] != 0 or G[i] != 0):
        arr[0][i] = np.right_shift(arr_intermediate[0][i],27)
        arr[1][i] = np.right_shift(arr_intermediate[1][i],27)
        arr_intermediate[0][i] = np.right_shift(arr_intermediate[0][i],14)#14
        arr_intermediate[1][i] = np.right_shift(arr_intermediate[1][i],14)

        if(arr[0][i]!=0 or arr[1][i]!=0 or True):#arr[0][i-2]>0 or arr[1][i-2]>0):
            if (debug>1):
                print("i=%s"%i)
                print("C[0]: %s"%C[0])
                print("C[1]: %s"%C[1])
                print("C[2]: %s"%C[2])
                print("C[3]: %s"%C[3])
                print("arr_intermediate[0][i-2]: %s"%arr_intermediate[0][i-2])
                print("arr_intermediate[1][i-2]: %s"%arr_intermediate[1][i-2])          
                print("F[%s]: %s"%(i,F[i]))
                print("G[%s]: %s"%(i,G[i]))
                print("arr_intermediate[0][i]: %s"%(arr_intermediate[0][i]))
                print("arr_intermediate[1][i]: %s"%(arr_intermediate[1][i]))
                print("arr[0][i] after: %s"%(arr[0][i]))
                print("arr[1][i] after: %s"%(arr[1][i]))
                print("\n")

        # THIS IS NOT RECURSIVE B/C WE DO NOT TOUCH THE SECOND INDEX
        # print("DEBUG: I'm zero-ing samples 1-8")
        for j in range(2, samp_per_clock):
            if decimate:
                arr[j][i] = 0# DEBUG
            else:
                # print(a1)\
                arr[j][i] +=  -1*(np.right_shift(a1*arr[j-1][i],14) + np.right_shift(a2*arr[j-2][i],14))
                # arr[j][i] +=  -1*(a1*np.right_shift(arr_intermediate[j-1][i],13) + a2*np.right_shift(arr_intermediate[j-2][i],13))
                # arr_intermediate[j][i] -= a1*np.right_shift(arr_intermediate[j-1][i],0) + a2*np.right_shift(arr_intermediate[j-2][i],0)
                # arr[j][i] = (arr_intermediate[j][i])/(2**13)
    # print(arr)
    # now transpose arr and flatten
    output = arr.transpose().reshape(-1) 
    
    return output 


def iir_biquad_run_fixed_point_extended(ins, coeffs, samp_per_clock=8, ics=None, manual_filter=False, decimate=True, a1=0, a2=0, fixed_point=False, debug=0, added_precision=0):
    if ics is None:
        # Debugging
        if debug>1:
            print("No initial conditions!")
        ics = np.zeros(samp_per_clock*3)
        ics = ics.reshape(3,-1)
    ins = np.array(ins, dtype=np.int64)
    coeffs = np.array(coeffs, dtype=np.int64)
    # Expand the inputs with the initial conditions
    newins = np.concatenate( (ics[0],ins) )

    f_fir = coeffs[0:samp_per_clock-2]
    g_fir = coeffs[samp_per_clock-2:2*samp_per_clock-3]
    D_FF = coeffs[2*samp_per_clock-3 + 0]
    D_FG = coeffs[2*samp_per_clock-3 + 1]
    E_GF = coeffs[2*samp_per_clock-3 + 2]
    E_GG = coeffs[2*samp_per_clock-3 + 3]
    C = coeffs[2*samp_per_clock-3 + 4:2*samp_per_clock-3 + 4 + 4]
    # print(C.dtype)

    
    if (debug>1):
        print("f fir: %s"%f_fir)
        print("g fir: %s"%g_fir)
        for i in range(len(newins)):
            if(newins[i] != 0):
                print("newins index %s: %s"%(i, newins[i]))
    
    # Run the FIRs
    if(manual_filter):
        raise Exception("Not implemented yet")
    else:
        f = signal.lfilter( f_fir, [1], newins )#/(2**14) # This will treat negatives wrong if you are using twos complement
        g = signal.lfilter( g_fir, [1], newins )#/(2**14)
        # Now we decimate f/g by 8, because we only want the 0th and 1st samples out of 8 for each.
    
    f = f.reshape(-1, samp_per_clock).transpose()[0]
    g = g.reshape(-1, samp_per_clock).transpose()[1]
    
    if (debug>1):
        print("HERE 2")
        for i in range(len(f)):
            if(f[i] != 0):
                print("f index %s: %s"%(i, f[i]))
        for i in range(len(g)):
            if(g[i] != 0):
                print("g index %s: %s"%(i, g[i]))
            # print("g index shifted %s: %s"%(i, g[i]/(2**14)))
    # n.b. f[0]/g[0] are initial conditions

    # f[2] (real sample 8) is calculated from 8, 7, 6, 5, 4, 3, 2.
    # g[2] (real sample 9) is calculated from 9, 8, 7, 6, 5, 4, 3, 2.

    # Now we need to compute the F and G functions, which *again* are just FIRs,
    # however they're cross-linked, so it's a little trickier.
    # We split it into
    # F = (fir on f) + G_coeff*g(previous clock)
    # G = (fir on g) + F_coeff*f(previous clock)
    
    F_fir = [ 2**(14+added_precision), D_FF ] # This is for sample 0 # WAS 2**14
    G_fir = [ 2**(14+added_precision), E_GG ] # This is for sample 1

    
    if (debug>1):
        # Debugging
        print("F/G FIRs operate on f/g inputs respectively")
        print("D_FF:", D_FF, " D_FG:", D_FG)
        print("E_GG:", E_GG, " E_GF:", E_GF)
        print()

    # Filter them
    F = signal.lfilter( F_fir, [1], f )#/(2**14) # The 14 bit shift will come later, with the lookbacks
    G = signal.lfilter( G_fir, [1], g )#/(2**14)

    # Now we need to feed the f/g paths into the opposite filter
    # F[0]/G[0] are going to be dropped anyway.
    F[1:] += D_FG*g[0:-1]#/(2**14)
    G[1:] += E_GF*f[0:-1]#/(2**14)    

    
    if (debug>1):
        print("HERE 3")
        for i in range(len(F)):
            if(F[i] != 0):
                print("F index %s: %s"%(i, F[i]))
        for i in range(len(G)):
            if(G[i] != 0):
                print("G index %s: %s"%(i, G[i]))
    
    # drop the initial conditions
    F = np.array(np.floor(F[1:]), dtype=np.int64)
    G = np.array(np.floor(G[1:]), dtype=np.int64)
    
    # Now reshape our outputs.
    arr = np.array(ins.reshape(-1, samp_per_clock).transpose(), dtype=np.int64)
    arr_intermediate = np.array(ins.reshape(-1, samp_per_clock).transpose(), dtype=np.int64)
    # arr[0] is now every 0th sample (e.g. for samp_per_clock = 8, it's 0, 8, 16, 24, etc.)
    # arr[1] is now every 1st sample (e.g. for samp_per_clock = 8, it's 1, 9, 17, 25, etc.)
    # Debugging
    
    if (debug>1):
        print("Update step (matrix) coefficients:", C)
        print("As an IIR: (Lucas thinks there is a typo here)")
        print("y[0] =", C[1], "*z^-", samp_per_clock*2-1," + ", C[0], "*z^-", samp_per_clock*2,
              "+F[0]",sep='')
        print("y[1] =", C[3], "*z^-", samp_per_clock*2," + ", C[2], "*z^-", samp_per_clock*2+1,
              "+G[1]",sep='')
    # Now compute the IIR.
    # INITIAL CONDITIONS STEP
    y0_0 =  C[0]*ics[1][0] + C[1]*ics[1][1] + F[0]
    y1_0 =  C[2]*ics[1][0] + C[3]*ics[1][1] + G[0]
    y0_1 =  C[0]*ics[2][0] + C[1]*ics[2][1] + F[1]
    y1_1 =  C[2]*ics[2][0] + C[3]*ics[2][1] + G[1]
    for i in range(len(arr[0])):
        if i == 0:
            # Compute from initial conditions.
            arr_intermediate[0][i] = np.int64(C[0]*y0_0 + C[1]*y1_0 + np.right_shift(F[i],1))
            arr_intermediate[1][i] = np.int64(C[2]*y0_0 + C[3]*y1_0 +np.right_shift(G[i],1))
        elif i==1:
            # Compute from initial conditions
            arr_intermediate[0][i] = np.int64(C[0]*y0_1 + C[1]*y1_1 + np.right_shift(F[i],1))
            arr_intermediate[1][i] = np.int64(C[2]*y0_1 + C[3]*y1_1 + np.right_shift(G[i],1))
        else:
            # THIS IS THE ONLY RECURSIVE STEP
            # FIRS come in in Q21.27, but were multiplied by Q
            # A regiter has 13 fractional bits
            # B register (Coefficient) has 14 fractional bits
            # C register (fir add) therefore has to be 27 to match, but was multiplied by Q4.14 coefficients twice.
            arr_intermediate[0][i] = np.int64(C[0]*np.right_shift(arr_intermediate[0][i-2],0)
                                              + C[1]*np.right_shift(arr_intermediate[1][i-2],0)
                                              + np.right_shift(F[i],1))
            #1 The A register (the feedback) has 13 Fractional bits. The FIRs went through 2 rounds of 14 fractional bit coeffs, and only had one removed
            arr_intermediate[1][i] = np.int64(C[2]*np.right_shift(arr_intermediate[0][i-2],0)
                                              + C[3]*np.right_shift(arr_intermediate[1][i-2],0)
                                              + np.right_shift(G[i],1))
            if debug >=1 and (arr_intermediate[0][i] != 0 or arr_intermediate[1][i] != 0):
                print("Sample %d: F=%s, G=%s, arr_intermediate[0][i-2]=%s, arr_intermediate[1][i-2]=%s"%(i*8, 
                                                                                                         F[i], 
                                                                                                         G[i], 
                                                                                                         arr_intermediate[0][i-2],
                                                                                                         arr_intermediate[1][i-2]))
            
            # if(F[i] != 0 or G[i] != 0):
        arr[0][i] = np.right_shift(arr_intermediate[0][i],27+added_precision*2)
        arr[1][i] = np.right_shift(arr_intermediate[1][i],27+added_precision*2)
        arr_intermediate[0][i] = np.right_shift(arr_intermediate[0][i],14+added_precision)#14
        arr_intermediate[1][i] = np.right_shift(arr_intermediate[1][i],14+added_precision)

        if(arr[0][i]!=0 or arr[1][i]!=0 or True):#arr[0][i-2]>0 or arr[1][i-2]>0):
            if (debug>1):
                print("i=%s"%i)
                print("C[0]: %s"%C[0])
                print("C[1]: %s"%C[1])
                print("C[2]: %s"%C[2])
                print("C[3]: %s"%C[3])
                print("arr_intermediate[0][i-2]: %s"%arr_intermediate[0][i-2])
                print("arr_intermediate[1][i-2]: %s"%arr_intermediate[1][i-2])          
                print("F[%s]: %s"%(i,F[i]))
                print("G[%s]: %s"%(i,G[i]))
                print("arr_intermediate[0][i]: %s"%(arr_intermediate[0][i]))
                print("arr_intermediate[1][i]: %s"%(arr_intermediate[1][i]))
                print("arr[0][i] after: %s"%(arr[0][i]))
                print("arr[1][i] after: %s"%(arr[1][i]))
                print("\n")

        # THIS IS NOT RECURSIVE B/C WE DO NOT TOUCH THE SECOND INDEX
        # print("DEBUG: I'm zero-ing samples 1-8")
        for j in range(2, samp_per_clock):
            if decimate:
                arr[j][i] = 0# DEBUG
            else:
                # print(a1)\
                # print(type(a1))
                # print(type(arr[j-1][i]))
                arr[j][i] +=  -1*(np.right_shift(a1*arr[j-1][i],14+added_precision) + np.right_shift(a2*arr[j-2][i],14+added_precision))
                # arr[j][i] +=  -1*(a1*np.right_shift(arr_intermediate[j-1][i],13) + a2*np.right_shift(arr_intermediate[j-2][i],13))
                # arr_intermediate[j][i] -= a1*np.right_shift(arr_intermediate[j-1][i],0) + a2*np.right_shift(arr_intermediate[j-2][i],0)
                # arr[j][i] = (arr_intermediate[j][i])/(2**13)
    # print(arr)
    # now transpose arr and flatten
    output = arr.transpose().reshape(-1) 
    
    return output 

def manual_fir_pole_section_convert(coeffs, x, coeff_int, coeff_frac, data_int, data_frac, out_int=22, out_frac=26):


    # Sneaky reuse, clean up later
    return manual_fir_section_convert(coeffs, x, coeff_int, coeff_frac, data_int, data_frac, out_int, out_frac)

    # For pole FIR
    #we get inputs in Q14.2 format. (NBITS-NFRAC, NFRAC)
    #Internally we compute in Q21.27 format, coefficients in Q4.14 format
    #So we shift to Q17.13 format.   
#     x = np.array(x)
#     y = np.zeros(len(x))
#     for coeff_set in coeffs:
#         for i in range(len(coeff_set), len(x)):
#             total = 0
#             for j in range(len(coeff_set)):
# #                 print(coeff_set[j])
#                 total += coeff_set[j] * x[i-j]
#             y[i] = total
#         x=np.copy(y)
#         y=np.zeros(len(x))
#     return x

def manual_fir_zero_section_convert(coeffs, x, coeff_int, coeff_frac, data_int, data_frac, out_int=22, out_frac=26):
    # Each set of coefficients in the list is an FIR in series
    # This may need removed in the future
    
    # For zero FIR
    #coeffs in Q4.14
    #data in  Q18.12 and Q15.12
    #trim to  Q14.12 for the preadder
    #intermediate in Q22.26   
    
    # Sneaky reuse, clean up later
    return manual_fir_section_convert(coeffs, x, coeff_int, coeff_frac, data_int, data_frac, out_int, out_frac)

def manual_fir_section(coeffs, x):
    # Each set of coefficients in the list is an FIR in series
    # This may need removed in the future
    
    # For zero FIR
    #coeffs in Q4.14
    #data in  Q18.12 and Q15.12
    #trim to  Q14.12 for the preadder
    #intermediate in Q22.26   
    
    for coeff_set in coeffs:
        for c in coeff_set:
            if(c >= 2**18 or c < -1*(2**18)):
                raise Exception("Coefficient out of bounds")
    
    x = np.array(x)
    y = np.zeros(len(x))
    for coeff_set in coeffs:
        for i in range(len(coeff_set), len(x)):
            total = 0
            for j in range(len(coeff_set)):
                total += coeff_set[j] * x[i-j]
            y[i] = total#/(2**26)
#             if(total>0):
#                 print(total)
#                 print(y[i])
        x=np.copy(y)
        y=np.zeros(len(x))
    return x

def manual_fir_pole_section(coeffs, x):
    
    # Sneaky reuse, clean up later
    return manual_fir_section(coeffs, x)

def manual_fir_zero_section(coeffs, x):
    
    # Sneaky reuse, clean up later
    return manual_fir_section(coeffs, x)


def manual_iir_section(coeffs, y):
    y = np.array(y)
    for coeff_set in coeffs:
        for i in range(len(coeff_set), len(y)):
            total = coeff_set[0] * y[i]
            for j in range(1,len(coeff_set)):
#                 print(coeff_set[j])
                total -= coeff_set[j] * y[i-j]
            y[i] = total
    return y

