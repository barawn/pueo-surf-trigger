import pickle
import argparse
import itertools
import io
from pprint import pprint

def meta_indices( beams, mask ):
    """ Returns list of beams have the specified bits set in the L2 Mask. """
    return [ b['Index'] for b in filter(lambda x : x['L2Mask'] & mask, beams)]

def beam_adder_indices( beams, left, right, top ):
    """ Returns the adder (sub-beam) indices for all the beams. 255 = no sub-beam """
    indices = []
    for b in beams:
        leftIndex = left.index(b['LeftDelays'])
        rightIndex = right.index(b['RightDelays'])
        if b['TopDelays'] is not None:
            topIndex = top.index(b['TopDelays'])
        else:
            topIndex = 255
        indices.append( (leftIndex, rightIndex, topIndex) )
    return indices                               

def transform_adders( adders, delayName, offsetName, beams, verbose=True):
    """ Find the minimum offset of an adder and integrate it into the delay """
    transformed = []
    for adder in adders:
        selected = list(filter(lambda x : (x[delayName] == adder), beams))
        offsets = [ x[offsetName] for x in selected ]
        minOffset = min(offsets)
        maxOffset = max(offsets)
        if verbose:
            print(f'Adder {adder} used in {len(selected)} beams: min/max offsets {minOffset} / {maxOffset}')
        newAdder = tuple(x+minOffset for x in adder)
        for b in selected:
            b[offsetName] -= minOffset
            b[delayName] = newAdder
        transformed.append(newAdder)
    return transformed

def sv_string(k, v):
    def print_to_string(*args, **kwargs):
        with io.StringIO() as output:
            print(*args, file=output, **kwargs)
            return output.getvalue()
    
    if type(v) == int:
        return f'\tlocalparam {k} = {v};'
    elif type(v) == list:
        l = len(v)
        s = f'\tlocalparam {k} [0:{l-1}]'
        if type(v[0]) == tuple:
            s += f'[0:{len(v[0])-1}] = \'{{\n'
            first = True
            for el in v:
                if not first:
                    s += ',\n'
                else:                    
                    first = False
                s += f'\t\t\'{{ {print_to_string(*el, sep=",", end="")} }}'
            s += ' };\n'
        else:
            s += ' = \'{\n'
            first = True
            for el in v:
                if not first:
                    s += ',\n'
                else:
                    first = False
                s += f'\t\t{el}'
            s += ' };\n'
        return s
    else:
        print(f'what type is this: {type(v)}')
    
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("infile", help="pickled beam file")
    parser.add_argument("outfile", help="output SV package")
    
    args = parser.parse_args()

    rawBeams = None
    with open(args.infile, 'rb') as f:
        rawBeams = pickle.load(f)

    NBEAMS = len(rawBeams)
    # make a simpler dictionary
    beams = []
    for b in rawBeams:
        bb = {}
        bb['LeftDelays'] = tuple(map(int, b['LeftAdder']))
        bb['LeftOffset'] = int(b['LeftOffset'])
        bb['RightDelays'] = tuple(map(int, b['RightAdder']))
        bb['RightOffset'] = int(b['RightOffset'])
        bb['TopDelays'] = tuple(map(int, b['TopAdder'])) if b['TopAdder'] is not None else None
        bb['TopOffset'] = int(b['TopOffset']) if b['TopOffset'] is not None else 0
        bb['Index'] = b['Index']
        bb['L2Mask'] = b['L2Mask']
        beams.append(bb)
        
    print(f'process_jjb: loaded {NBEAMS} beam(s)')

    # Get our parameters ready
    params = {}

    leftAdders = set()
    rightAdders = set()
    topAdders = set()
    for b in beams:
        leftAdders.add(b['LeftDelays'])
        rightAdders.add(b['RightDelays'])
        if b['TopDelays']:
            topAdders.add(b['TopDelays'])

    print(f'process_jjb: {len(leftAdders)}/{len(rightAdders)}/{len(topAdders)} adders')

    transformedLeft = transform_adders(leftAdders, 'LeftDelays', 'LeftOffset', beams)
    transformedRight = transform_adders(rightAdders, 'RightDelays', 'RightOffset', beams)
    # just to keep the naming the same, top adders always begin at 0
    transformedTop = list(topAdders)

    leftOffsets = [ b['LeftOffset'] for b in beams ]
    rightOffsets = [ b['RightOffset'] for b in beams ]
    topOffsets = [ b['TopOffset'] for b in beams ]    
    
    maxLeft = max(itertools.chain(*transformedLeft))
    maxRight = max(itertools.chain(*transformedRight))
    maxTop = max(itertools.chain(*transformedTop))

    maxLeftOffset = max(leftOffsets)
    maxRightOffset = max(rightOffsets)
    maxTopOffset = max(topOffsets)
    
    print(f'Transformed left adders (max delay {maxLeft} / max offset {maxLeftOffset}):')
    print(transformedLeft)
    print(f'Transformed right adders (max delay {maxRight} / max offset {maxRightOffset}):')
    print(transformedRight)
    print(f'Transformed top adders (max delay {maxTop} / max offset {maxTopOffset}):')
    print(transformedTop)

    maxAll = max((maxLeft, maxRight, maxTop))
    # if max is 23, for sample 0, we need to look back
    # 1 clock = max is z^-7
    # 2 clocks = max is z^-15
    # 3 clocks = max is z^-23
    # So the number of clocks to look back is (maxAll//8)+1
    # and the sample storage depth is (maxAll//8)+2
    # (the extra is for the undelayed inputs)
    maxDepth = maxAll//8 + 2
    print(f'Maximum sample delay is {maxAll} - sample store depth is {maxDepth}')
    maxLeftDepth = maxLeftOffset//8 + 2 if maxLeftOffset > 0 else 1
    print(f'Max left adder offset is {maxLeftOffset} - left store depth is {maxLeftDepth}')
    maxRightDepth = maxLeftOffset//8 + 2 if maxRightOffset > 0 else 1
    print(f'Max right adder offset is {maxRightOffset} - right store depth is {maxRightDepth}')
    maxTopDepth = maxTopOffset//8 + 2 if maxTopOffset > 0 else 1
    print(f'Max top adder offset is {maxTopOffset} - top store depth is {maxTopDepth}')

    meta0 = meta_indices(beams, 0x01)
    meta0 = meta0+[255]*(22-len(meta0)) if len(meta0) < 22 else meta0
    print(f'Bit 0 has beam indices: {meta0}')
    meta1 = meta_indices(beams, 0x02)
    meta1 = meta1+[255]*(22-len(meta1)) if len(meta1) < 22 else meta1
    print(f'Bit 1 has beam indices: {meta1}')
    meta2 = meta_indices(beams, 0x04)
    meta2 = meta2+[255]*(22-len(meta2)) if len(meta2) < 22 else meta2    
    print(f'Bit 2 has beam indices: {meta2}')
    meta3 = meta_indices(beams, 0x08)
    meta3 = meta3+[255]*(22-len(meta3)) if len(meta3) < 22 else meta3
    print(f'Bit 3 has beam indices: {meta3}')

    meta4 = meta_indices(beams, 0x10)
    meta4 = meta4+[255]*(22-len(meta4)) if len(meta4) < 22 else meta4
    print(f'Bit 4 has beam indices: {meta4}')    
    meta5 = meta_indices(beams, 0x20)
    meta5 = meta5+[255]*(22-len(meta5)) if len(meta5) < 22 else meta5
    print(f'Bit 5 has beam indices: {meta5}')
    meta6 = meta_indices(beams, 0x40)
    meta6 = meta6+[255]*(22-len(meta6)) if len(meta6) < 22 else meta6
    print(f'Bit 6 has beam indices: {meta6}')
    meta7 = meta_indices(beams, 0x80)
    meta7 = meta7+[255]*(22-len(meta7)) if len(meta7) < 22 else meta7
    print(f'Bit 7 has beam indices: {meta7}')    

    print("Determining beam indices.")
    indices = beam_adder_indices(beams, transformedLeft, transformedRight, transformedTop)
    
    params['SAMPLE_STORE_DEPTH'] = maxDepth
    params['LEFT_ADDER_LEN'] = len(transformedLeft)
    params['LEFT_STORE_DEPTH'] = maxLeftDepth
    params['RIGHT_ADDER_LEN'] = len(transformedRight)
    params['RIGHT_STORE_DEPTH'] = maxRightDepth
    params['TOP_ADDER_LEN'] = len(transformedTop)
    params['TOP_STORE_DEPTH'] = maxTopDepth

    # these are all fixed length
    params['META0_INDICES'] = meta0
    params['META1_INDICES'] = meta1    
    params['META2_INDICES'] = meta2
    params['META3_INDICES'] = meta3    
    params['META4_INDICES'] = meta4
    params['META5_INDICES'] = meta5    
    params['META6_INDICES'] = meta6
    params['META7_INDICES'] = meta7

    # This order doesn't matter, we look up each beam's index later.
    # The BEAM indices do matter thanks to meta indexing

    params['LEFT_ADDERS'] = transformedLeft
    params['RIGHT_ADDERS'] = transformedRight
    params['TOP_ADDERS'] = transformedTop

    params['BEAM_INDICES'] = indices
    params['BEAM_LEFT_OFFSETS'] = leftOffsets
    params['BEAM_RIGHT_OFFSETS'] = rightOffsets
    params['BEAM_TOP_OFFSETS'] = topOffsets

    with open(args.outfile, 'w') as f:
        print('package pueo_beams;', file=f)
        
        for k, v in params.items():
            print(sv_string(k,v), file=f)
            print('', file=f)

        print('endpackage', file=f)
        
