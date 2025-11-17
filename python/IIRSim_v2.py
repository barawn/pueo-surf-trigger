import numpy as np
from matplotlib import pyplot as plt
from scipy.signal import lfilter
from scipy import signal
import scipy
import math
from scipy.special import eval_chebyu


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

