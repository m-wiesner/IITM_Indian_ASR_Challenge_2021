#!/usr/bin/env python
import numpy as np
import argparse
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.preprocessing import normalize
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components
import os
import matplotlib

matplotlib.use('Agg')
from matplotlib import pyplot as plt
import seaborn as sns


class KaldiDataDir(object):
    def __init__(self, dirname):
        self.path = dirname
        self.segments = None
        self.wavscp = None
        
        if not os.path.isdir(dirname):
            raise ValueError('{} does not exist'.format(dirname))
        
        for fname in ('segments', 'wav.scp'):
            if os.path.exists(self.path + '/' + fname):
                with open('/'.join([self.path, fname]), 'r', encoding='utf-8') as f:
                    key_value = self.load_file(f)
                    if fname == 'segments':
                        self.segments = key_value
                    elif fname == 'wav.scp':
                        self.wavscp = key_value
        print()

    def load_file(self, f):
        key_value = {}
        for l in f:
            key, val = l.strip().split(None, 1) 
            key_value[key] = val
        return key_value

    def remap_recoids(self, mapping):
        for k in mapping:
            k_val = self.wavscp.pop(k)
            self.wavscp[mapping[k]] = k_val
        segment_keys = self.segments.keys()
        for k in segment_keys:
            recoid, start, end = self.segments[k].split()             
            if recoid in mapping:
                recoid = mapping[recoid] 
            self.segments[k] = ' '.join([recoid, start, end])
            
    def update_recoids(self, mapping):
        self.remap_recoids(mapping)
        with open('/'.join([self.path, 'segments']), 'w', encoding='utf-8') as f:
            for k, v in self.segments.items():
                print('{} {}'.format(k, v), file=f)
        
        with open('/'.join([self.path, 'wav.scp']), 'w', encoding='utf-8') as f:
            for k, v in self.wavscp.items():
                print('{} {}'.format(k, v), file=f)

    def write_reco2prompt(self, reco2prompt):
        with open('/'.join([self.path, 'reco2prompt']), 'w', encoding='utf-8') as f:
            for r in reco2prompt:
                print('{} {}'.format(r, reco2prompt[r]), file=f)


def load_segments(lines, recos):
    for l in lines:
        segid, recoid, start, stop = l.strip().split()
        if '_long_' in recoid:
            if recoid not in recos:
                recos[recoid] = {'segs': [], 'text': []}
            recos[recoid]['segs'].append((segid, float(start), float(stop)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('datadir')
    parser.add_argument('--sim-thresh', type=float, default=0.9)
    parser.add_argument('--plot', action='store_true')
    args = parser.parse_args()

    # Load segments
    recos = {}
    train_lines = open(args.datadir + '/segments').readlines()
    load_segments(train_lines, recos)   
 
    for recoid in recos:
        recos[recoid]['segs'] = sorted(recos[recoid]['segs'], key=lambda x: x[1])
    
    # Load text
    text = dict(l.strip().split(None, 1) for l in open(args.datadir + '/text', encoding='utf-8').readlines())
   
    # Merge text across segments
    for recoid in recos:
        for s in recos[recoid]['segs']:
            recos[recoid]['text'].append(text[s[0]])
    for recoid in recos:
        recos[recoid]['text'] = ' '.join(recos[recoid]['text'])
   
    # Embed text 
    print("Embedding text ...")
    vectorizer = CountVectorizer(strip_accents='unicode', ngram_range=(4,4))
    vectorizer.fit([x[1]['text'] for x in sorted(recos.items(), key=lambda x: x[0])])
    
    feats = vectorizer.transform([x[1]['text'] for x in sorted(recos.items(), key=lambda x: x[0])])
    feats_norm = normalize(feats, norm='l2', axis=1)
    
    # Get similarity matrix
    conf_mat = np.dot(feats_norm, feats_norm.T)
    if args.plot:
        plt.figure()
        sns.kdeplot(conf_mat[np.triu_indices_from(conf_mat.todense(), k=1)].tolist()[0])
        plt.xlabel('similarity')
        plt.yscale('log')
        plt.savefig('{}/confmat_hist.png'.format(args.datadir))
    
     
    # Get connected components (Unique recordings transcripts)
    print("Computing adjacency matrix ...")
    adj_mat = np.zeros(conf_mat.shape)
    adj_mat[(conf_mat > args.sim_thresh).todense()] = 1
    graph = csr_matrix(adj_mat)
    n_components, labels = connected_components(csgraph=graph, directed=False, return_labels=True)
   
    # Assign story id to each recording
    print("Assigning story ids ...") 
    recos_sorted = sorted(recos.keys())
    new_labels = {}
    for i in range(n_components):
        new_labels.update({recos_sorted[j[0]]:i for j in np.argwhere(labels == i)})
   
    # Assign a new recoid to each "long" recording based on the new story id
    new_long_labels = {}
    new_recos = {}
    for recoid in new_labels:
        if "long" in recoid:
            spkid = '_'.join(recoid.split('_')[0:2])
            storyid = new_labels[recoid]
            if (spkid, storyid) not in new_recos:
                new_recos[(spkid, storyid)] = -1
            new_recos[(spkid, storyid)] += 1
            new_id = '{}_{:03d}_long_{:05d}'.format(spkid, new_recos[(spkid, storyid)], storyid)
            new_long_labels[recoid] = new_id
   
    dd = KaldiDataDir(args.datadir)
    dd.update_recoids(new_long_labels)
    dd.write_reco2prompt(new_labels)


if __name__ == "__main__":
    main()
