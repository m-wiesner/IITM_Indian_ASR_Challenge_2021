
import argparse
import sys
import os
import json
try:
    import openfst_python as fst
except ImportError:
    from pip._internal import main as pip
    pip(['install', 'openfst-python'])
    import openfst_python as fst


def _load_units(f):
    units = {}
    for l in f:
        val, idx = l.strip().split(None, 1)
        units[val] = int(idx)
    return units


def make_fst(isyms, osyms, sos='<s>', ctc_blank='<ctc_blank>', maps={}, repeat_cost=0.5):
    isym_sos_idx = isyms.get(sos, None)
    osym_sos_idx = osyms.get(sos, None)
    blank_idx = isyms.get(ctc_blank, None)

    # Create Empty FST
    H = fst.Fst()
    
    # Add states and arc 1 ---- <eps>:<s> / 1 -----> 0 ----> ...
    s0 = H.add_state()
    s_start = H.add_state()
    H.set_start(s_start)
    H.set_final(s0, fst.Weight.One(H.weight_type()))
    H.add_arc(H.start(), fst.Arc(0, osym_sos_idx, fst.Weight.One(H.weight_type()), s0))
    state2sym = {}
    sym2int = {}
    int2sym = {}
    for u in isyms:
        if u in ('<eps>', ctc_blank): 
            continue;
        s = H.add_state()
        state2sym[s] = u
        H.set_final(s, fst.Weight.One(H.weight_type()))
         
    # Add arcs
    for s in H.states():
        if s == s0:
            H.add_arc(
                s0,
                fst.Arc(
                    blank_idx, 0,
                    fst.Weight(H.weight_type(), repeat_cost), s0
                )
            )
        if s > 1:
            # state s0 to state s representing symbol state2sym[s]
            sym = state2sym[s]
            osym = maps[sym] if sym in maps else osyms[sym] 
            H.add_arc(s0, fst.Arc(isyms[sym], osym, fst.Weight.One(H.weight_type()), s))
            # symbol to blank (start state)
            H.add_arc(
                s,
                fst.Arc(
                    blank_idx, 0,
                    fst.Weight(H.weight_type(), repeat_cost), s0
                )
            )
            # self-loop
            H.add_arc(
                s,
                fst.Arc(
                    isyms[sym], 0,
                    fst.Weight(H.weight_type(), repeat_cost), s
                )
            )
            # symbol i to all other symbols except blank
            for t in H.states():
                if t > 1 and t != s:
                    sym_t = state2sym[t]
                    osym = maps[sym_t] if sym_t in maps else osyms[sym_t] 
                    H.add_arc(s, fst.Arc(isyms[sym_t], osym, fst.Weight.One(H.weight_type()), t)) 
    H.arcsort(sort_type='olabel')
    return H, sym2int 


def main():
    parser = argparse.ArgumentParser(
        'This script makes the HMM for CTC models'
    )
    parser.add_argument('isymbols', help='file with list of the ctc units in the '
        'first column', type=str
    )
    parser.add_argument('osymbols', help='file with list of the spm units in the '
        'first column', type=str
    )
    parser.add_argument('outname', help='name of the output. 2 files will be'
        ' created: (1) is an fst, (2) are the input symbols. They will have '
        ' different extentions but share the same name.', type=str
    )
    parser.add_argument('--sos', type=str, default='<s>')
    parser.add_argument('--ctc-blank', type=str, default='<ctc_blank>')
    parser.add_argument('--maps', default="",
        help='Comma separated input-output merges to make. Merges are '
        'separated by space, i.e. --maps <unk>,[unknown] colour,color'
    )
    parser.add_argument('--repeat-cost', type=float, default=0.5)
    args = parser.parse_args()

    with open(args.isymbols, 'r', encoding='utf-8') as f:
        isymbols = _load_units(f) 
    with open(args.osymbols, 'r', encoding='utf-8') as f:
        osymbols = _load_units(f) 

    maps = {}
    for m in args.maps.split():
        isym, osym = m.split(',')
        maps[isym] = osymbols[osym]
    print("Maps:", maps) 
    H, words_ = make_fst(
        isymbols, osymbols, sos=args.sos, ctc_blank=args.ctc_blank, maps=maps,
        repeat_cost=args.repeat_cost,
    )
    H.write(args.outname)

if __name__ == "__main__":
    main()
