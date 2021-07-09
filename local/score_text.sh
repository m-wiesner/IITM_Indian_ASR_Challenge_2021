#!/bin/bash

. ./path.sh
. ./cmd.sh

min_lmwt=4
max_lmwt=16
wips="0.0 0.5 1.0"
spm=false
whitespace="#"

. ./utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: ./local/score_text.sh <data> <words> <decode>"
  exit 1;
fi

data=$1
words=$2
decode=$3

if $spm; then
  echo "Not Implemented"
else
  mkdir -p ${decode}/scoring_kaldi/penalty_${wip}/log
  for wip in $wips; do
    $train_cmd LMWT=$min_lmwt:$max_lmwt ${decode}/scoring_kaldi/penalty_${wip}/log/best_path.LMWT.log \
      lattice-scale --inv-acoustic-scale=LMWT ark:"gunzip -c ${decode}/lat.1.gz |" ark:- \| \
      lattice-add-penalty --word-ins-penalty=${wip} ark:- ark:- \| \
      lattice-best-path --word-symbol-table=${words} ark:- ark,t:- \| \
      ./utils/int2sym.pl -f 2- ${words} '>' ${decode}/scoring_kaldi/penalty_${wip}/text.LMWT.hyp.tmp || exit 1;
  done
    
  for wip in ${wips}; do
    echo ${wip}
    for LMWT in `seq $min_lmwt $max_lmwt`; do 
      paste -d' ' <(awk '{print $1}' ${data}/text) <(cut -d' ' -f2- ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp.tmp) \
        > ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp.spm
      LC_ALL= python local/spm_to_word.py --whitespace ${whitespace} ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp.spm > ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp 
      cat ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp |\
        LC_ALL= sed 's/<unk>//g' |\
        compute-wer --mode=present ark:${data}/text ark:- \
        > ${decode}/scoring_kaldi/penalty_${wip}/wer_${LMWT}
      cat ${decode}/scoring_kaldi/penalty_${wip}/text.${LMWT}.hyp |\
        LC_ALL= sed 's/<unk>[^ ]*/<unk>/g' |\
        compute-wer --mode=present ark:${data}/text ark:- \
        > ${decode}/scoring_kaldi/penalty_${wip}/wer_${LMWT}_unk
    done
  done
fi
