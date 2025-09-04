import pickle
import argparse
import itertools

def meta_indices( beams, mask ):
    """ finish this later """
    return None

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

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("filename", help="pickled beam file")

    args = parser.parse_args()

    rawBeams = None
    with open(args.filename, 'rb') as f:
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
    transformedTop = topAdders

    maxLeft = max(itertools.chain(*transformedLeft))
    maxRight = max(itertools.chain(*transformedRight))
    maxTop = max(itertools.chain(*transformedTop))

    maxLeftOffset = max([ b['LeftOffset'] for b in beams ])
    maxRightOffset = max([ b['RightOffset'] for b in beams ])
    maxTopOffset = max([ b['TopOffset'] for b in beams ])
    
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
    
    params['SAMPLE_STORE_DEPTH'] = maxDepth
    params['LEFT_ADDERS'] = len(transformedLeft)
    params['LEFT_STORE_DEPTH'] = maxLeftDepth
    params['RIGHT_ADDERS'] = len(transformedRight)
    params['RIGHT_STORE_DEPTH'] = maxRightDepth
    params['TOP_ADDERS'] = len(transformedTop)
    params['TOP_STORE_DEPTH'] = maxTopDepth
