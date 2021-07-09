import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('text')
    parser.add_argument('--whitespace', default='\u2581')
    parser.add_argument('--nonspeech-mark', default='<')
    parser.add_argument('--unk', default='<unk>')

    args = parser.parse_args()

    with open(args.text, 'r', encoding='utf-8') as f:
        for l in f:
            try: 
                uttid, text = l.strip().split(None, 1)
                words = text.split()
                words_filt = list(filter(lambda a: a not in ('<s>', '</s>'), words))
                new_words = []
                for w in words_filt:
                    if w == args.unk:
                        new_words.append(' ' + args.unk)
                    else:
                        new_words.append(w.replace(args.whitespace, ' '))
                    #if w.startswith(args.nonspeech_mark):
                    #    new_words.append(' ' + w)
                    #else:
                    #    new_words.append(w.replace(args.whitespace, ' '))
            except ValueError:
                uttid = l.strip()
                new_words = [] 
            print(u'{} {}'.format(uttid, ''.join(new_words).strip()))

if __name__ == "__main__":
    main()
