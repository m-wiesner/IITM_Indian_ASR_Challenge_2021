#!/bin/bash

data_root=$1 #/export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database
lang=$2
odict=$3

orig_lexicon=${data_root}/${lang}/dictionary/${lang}_lexicon.txt
mkdir -p ${odict} 
grep -v "<" ${orig_lexicon} | sed 's/\([0-9]+\)//' > ${odict}/nonsilence_lexicon.txt
echo -e "<Noise\>\tSIL\n<silence>\tSIL\n<unk>\tSIL" > ${odict}/silence_lexicon.txt
cat ${odict}/{nonsilence,silence}_lexicon.txt | LC_ALL=C sort > ${odict}/lexicon.txt
python local/prepare_dict.py --silence-lexicon ${odict}/silence_lexicon.txt \
  ${odict}/lexicon.txt ${odict}


