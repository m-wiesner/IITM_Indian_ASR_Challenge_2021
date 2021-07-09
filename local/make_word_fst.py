#! /usr/bin/env python

import argparse
try:
    import openfst_python as fst
except ImportError:
    from pip._internal import main as pip
    pip(['install', 'openfst-python'])
    import openfst_python as fst


def _load_lexicon(f):
    lexicon = {}
    for l in f:
        w, pron = l.strip().split(None, 1) 
        assert w not in lexicon, "Error: Repeated word."
        lexicon[w] = pron.split()
        lexicon[w].insert(0, '#') 
    return lexicon


def _load_units(f):
    units = {}
    for l in f:
        try:
            u, i = l.strip().split(None, 1)     
        except ValueError:
            u = l.strip()
            i = 1 
        assert u not in units, "Error: Repeated units."
        units[u] = int(i)
    return units


def make_lexicon_fst(lexicon, words, graphemes,
    unk='[unknown]', unk_cost=0.5, whitespace='#', nlsyms={},
):
    L = fst.Fst()
    start = L.add_state()
    L.set_start(start)
    for w in lexicon:
        s0 = start
        for i, g in enumerate(lexicon[w]):
            s = L.add_state()
            consume_symbol=0
            if i == 0:
                consume_symbol = words[w]
            L.add_arc(
                s0,
                fst.Arc(
                    consume_symbol, graphemes[g],
                    fst.Weight.One(L.weight_type()), s
                )
            )
            # Consume arbitrary number of whitespaces before word
            if i == 0:
                L.add_arc(
                    s,
                    fst.Arc(
                        0, graphemes[whitespace],
                        fst.Weight.One(L.weight_type()), s
                    )
                )
            s0 = s
        L.set_final(s, fst.Weight.One(L.weight_type()))   
    
    # We add one final path for [unk] words. It accepts whitespace followed by
    # any number of non-initial graphemes
    if unk_cost != -1:
        s1_unk = L.add_state()
        L.add_arc(
            start,
            fst.Arc(
                words[unk], graphemes[whitespace],
                fst.Weight(L.weight_type(), unk_cost), s1_unk
            )
        )
        s2_unk = L.add_state()
        L.set_final(s2_unk, fst.Weight.One(L.weight_type()))  
         
        for g in graphemes:
            if (g not in nlsyms) and (g not in ('<eps>', whitespace)):
                L.add_arc(
                    s1_unk,
                    fst.Arc(
                        words[g], graphemes[g],
                        fst.Weight.One(L.weight_type()), s2_unk
                    )
                )
                L.add_arc(
                    s2_unk,
                    fst.Arc(
                        words[g], graphemes[g],
                        fst.Weight.One(L.weight_type()), s2_unk
                    )
                )
    return L 


def main():
    parser = argparse.ArgumentParser('Takes files word to grapheme mappings '
        'and creates an FST from it.'
    )
    parser.add_argument('words')
    parser.add_argument('graphemes') 
    parser.add_argument('lexicon')
    parser.add_argument('fst')
    parser.add_argument('--whitespace', type=str, default='#')
    parser.add_argument('--unk', type=str, default='[unknown]')
    parser.add_argument('--unk-cost', type=float, default=10.0, help="Cost of -1 is not used.")
    parser.add_argument('--nlsyms', default=None) 
   
    args = parser.parse_args()
     
    with open(args.words, 'r', encoding='utf-8') as f:
        words = _load_units(f)    
    
    with open(args.graphemes, 'r', encoding='utf-8') as f:
        graphemes = _load_units(f)    
    
    with open(args.lexicon, 'r', encoding='utf-8') as f:
        lexicon = _load_lexicon(f)

    with open(args.nlsyms, 'r', encoding='utf-8') as f:
        nlsyms = _load_units(f)

    L = make_lexicon_fst(lexicon, words, graphemes,
        unk=args.unk, unk_cost=args.unk_cost, whitespace=args.whitespace,
        nlsyms=nlsyms,
    )
    L.write(args.fst)


if __name__ == "__main__":
    main()
