#!/usr/bin/env python

import argparse
import os
import random


def load_segments(lines, recos, utt2spk):
    for l in lines:
        segid, recoid, start, stop = l.strip().split()
        if '_long_' in recoid:
            promptid = recoid.rsplit('_')[-1]
            if recoid not in recos:
                recos[recoid] = {'segs': [], 'prompt': promptid, 'spk': utt2spk[segid]}
            recos[recoid]['segs'].append((segid, float(start), float(stop)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('datadir')
    parser.add_argument('splits')
    parser.add_argument('--frac-heldout-prompt', type=float, default=0.03)
    parser.add_argument('--frac-heldout-spk', type=float, default=0.03)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    # Load speaker info
    utt2spk = dict(l.strip().split(None, 1) for l in open(args.datadir + '/utt2spk').readlines())
    recos = {}
    load_segments(open(args.datadir + '/segments').readlines(), recos, utt2spk)

    for recoid in recos:
        recos[recoid]['segs'] = sorted(recos[recoid]['segs'], key=lambda x: x[1])

    prompt2spks = {}
    spk2prompts = {}
    for recoid in recos:
        prompt = recos[recoid]['prompt']
        spk = recos[recoid]['spk']
        if prompt not in prompt2spks:
            prompt2spks[prompt] = []
        if spk not in spk2prompts:
            spk2prompts[spk] = []

        # Get list of speakers speaking each prompt
        prompt2spks[prompt].append(spk)
        # Get list of prompts spoken by each speaker
        spk2prompts[spk].append(prompt)

    # Sort the prompts and speakers on the basis of which promts had the
    # the fewest speaker, and which speakers read the fewest prompts.
    random.seed(args.seed)
    prompts = sorted(prompt2spks.items(), key=lambda x: (len(x[1]), random.random()))
    spks = sorted(spk2prompts.items(), key=lambda x: len(x[1])) 

    # Hold out some prompts that had the smallest number of spks
    ho_prompts = prompts[0:int(len(prompts) * args.frac_heldout_prompt)]
    # Hold out some spks that read the smallest number of prompts 
    ho_spks = spks[0:int(len(spks) * args.frac_heldout_spk)]

    # Get the spks to be heldout (those that read the heldout prompts)
    ho_prompt_spks = set(s for p in ho_prompts for s in p[1])
    # Get the promts to be heldout
    ho_spk_prompts = set(p for s in ho_spks for p in s[1])

    ho_prompts = [p[0] for p in ho_prompts]
    ho_spks = [s[0] for s in ho_spks]

    dev_sets = {
        'ho_prompt_and_spk': set(recoid for recoid, reco in recos.items() if reco['prompt'] in ho_prompts and reco['spk'] in ho_prompt_spks), 
        'ho_spks': set(recoid for recoid, reco in recos.items() if reco['spk'] in ho_prompt_spks),
        'ho_spk_and_prompt': set(recoid for recoid, reco in recos.items() if reco['prompt'] in ho_spk_prompts and reco['spk'] in ho_spks),
        'ho_prompts': set(recoid for recoid, reco in recos.items() if reco['prompt'] in ho_spk_prompts)
    }

    # Print splits to files created in the args.splits directory
    os.makedirs(args.splits, exist_ok=True)
    for ds in dev_sets:
        with open('{}/{}'.format(args.splits, ds), 'w') as f:    
            for recoid in dev_sets[ds]:
                print(recoid, file=f)
              

if __name__ == "__main__":
    main()
