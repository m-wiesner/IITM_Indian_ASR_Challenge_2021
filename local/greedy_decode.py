import kaldi_io
import argparse
from itertools import groupby 


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('posts')
    parser.add_argument('vocab')
    parser.add_argument('--sos', type=str, default='<s>')
    parser.add_argument('--eos', type=str, default='</s>')
    parser.add_argument('--ctc-blank-idx', type=int, default=0)
    parser.add_argument('--whitespace', default='\u2581')

    args = parser.parse_args()
    vocab = {args.ctc_blank_idx: '<ctc_blank>'}
    with open(args.vocab, 'r') as f:
        for l in f:
            sym, val = l.strip().split(None, 1)
            if int(val) == 0:
                continue;
            vocab[int(val)-1] = sym
            if sym == args.sos:
                sos_idx = int(val) - 1
            elif sym == args.eos:
                eos_idx = int(val) - 1

    for key, mat in kaldi_io.read_mat_ark(args.posts):
        transcript = []
        for frame in mat:
            idx_max = frame.argmax()
            transcript.append(idx_max)
        output_str_nodup = [vocab[w[0]] for w in groupby(transcript) if w[0] not in (args.ctc_blank_idx, sos_idx, eos_idx)]
        text = ''.join(output_str_nodup).replace(args.whitespace, ' ').strip()
        print('{} {}'.format(key, text))


if __name__ == "__main__":
    main()

