#!/usr/bin/env python
import argparse


def load_segments(lines, recos):
    for l in lines:
        segid, recoid, start, stop = l.strip().split()
        if 'long_' in recoid:
            if recoid not in recos:
                recos[recoid] = {'segs': [], 'text': []}
            promptid_ref = '_'.join(segid.split('_')[2:])
            promptid_hyp = recoid.rsplit('_', 1)[-1]
            recos[recoid]['ref'] = promptid_ref
            recos[recoid]['hyp'] = promptid_hyp
            recos[recoid]['segs'].append((segid, float(start), float(stop)))


def compute_recall(recos):
    ref2hyp = {}
    for reco in recos:
        ref_prompt = recos[reco]['ref']
        hyp_prompt = recos[reco]['hyp']
        if ref_prompt not in ref2hyp:
            ref2hyp[ref_prompt] = {}
        if hyp_prompt not in ref2hyp[ref_prompt]:
            ref2hyp[ref_prompt][hyp_prompt] = 0
        ref2hyp[ref_prompt][hyp_prompt] += 1
    ref2hyp_sorted = {p: sorted(ref2hyp[p].items(), key=lambda x: x[1], reverse=True) for p in ref2hyp}

    tot = 0.
    maj_class = 0.
    for p in ref2hyp_sorted:
        maj_class += ref2hyp_sorted[p][0][1]
        for q in ref2hyp_sorted[p]:
            tot += q[1]
    return maj_class / tot


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('datadir')
    args = parser.parse_args()

    recos = {}
    load_segments(open(args.datadir + '/segments').readlines(), recos) 
    recall = compute_recall(recos)    
    print(recall)


if __name__ == "__main__":
    main()


