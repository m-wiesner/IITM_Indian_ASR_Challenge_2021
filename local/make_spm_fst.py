import argparse
try:
    import openfst_python as fst
except ImportError:
    from pip._internal import main as pip
    pip(['install', 'openfst-python'])
    import openfst_python as fst


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


def make_spm_fst(spms, graphemes, nlsyms={}, add_nlsym_whitespace=True,
    whitespace_symbol='\u2581', replace_whitespace_symbol='#',
    sos='<s>', eos='</s>', unk='<unk>',
):
    L = fst.Fst()
    start = L.add_state()
    L.set_start(start)
    for w in spms:
        # Epsilon is not a real spm
        if w == "<eps>":
            continue;  
        
        s0 = start
        # Unk, start and end of sequence symbols are handled separately
        if w in (sos, eos, unk):
            s = L.add_state()
            L.add_arc(s0, fst.Arc(spms[w], 0, fst.Weight.One(L.weight_type()), s))
            L.set_final(s, fst.Weight.One(L.weight_type()))
            continue;

        # Non-speech words should sometimes be preceded by whitespace
        w_ = []
        if w in nlsyms:
            w_.append(replace_whitespace_symbol)
            if add_nlsym_whitespace:
                w_.append(w.replace(whitespace_symbol, replace_whitespace_symbol))
            else:
                w_.append(w.replace(whitespace_symbol, ''))
        elif whitespace_symbol in w: 
            w_ = w.replace(whitespace_symbol, replace_whitespace_symbol)
        else:
            w_ = w  
        # Make the fst path for each word
        for i, g in enumerate(w_):
            # This is the special SPM marking for whitespace
            s = L.add_state()
            consume_symbol = 0
            if i == 0:
                consume_symbol = spms[w]
            L.add_arc(
                s0,
                fst.Arc(
                    consume_symbol, graphemes[g],
                    fst.Weight.One(L.weight_type()), s
                ) 
            )
            s0 = s
        L.set_final(s, fst.Weight.One(L.weight_type())) 
    return L


def main():
    parser = argparse.ArgumentParser("Make SPM.fst that converts spm units"
        " to graphemes. This script assumes that the WFFST epsilon symbol is"
        " written as <eps>. It also assumes that a <s> and </s> exist"
        " indicating the start and end of sequence."
    )
    parser.add_argument("spm")
    parser.add_argument("graphemes")
    parser.add_argument("fst")
    parser.add_argument('--nlsyms', default=None, help="non linguistic symbols")
    parser.add_argument('--add-nlsym-whitespace', action='store_true')
    parser.add_argument('--whitespace-symbol', default='\u2581') 
    parser.add_argument('--replace-whitespace-symbol', default='#')
    parser.add_argument('--sos', default='<s>')
    parser.add_argument('--eos', default='</s>')
    parser.add_argument('--unk', default='<unk>')
    args = parser.parse_args()

    with open(args.spm, 'r', encoding='utf-8') as f:
        spms = _load_units(f)

    with open(args.graphemes, 'r', encoding='utf-8') as f:
        graphemes = _load_units(f)

    # Load and modify nlsyms
    nlsyms = {}
    if args.nlsyms is not None:
        with open(args.nlsyms, 'r', encoding='utf-8') as f:
            _nlsyms = _load_units(f)
        if not args.add_nlsym_whitespace:
            for k, v in _nlsyms.items():
                nlsyms[args.whitespace_symbol + k] = v
        else:
            nlsyms = _nlsyms
    L = make_spm_fst(spms, graphemes,
        nlsyms=nlsyms,
        add_nlsym_whitespace=args.add_nlsym_whitespace,
        whitespace_symbol=args.whitespace_symbol,
        replace_whitespace_symbol=args.replace_whitespace_symbol,
        sos=args.sos, eos=args.eos, unk=args.unk,
    )
     
    L.write(args.fst)


if __name__ == "__main__":
    main()
