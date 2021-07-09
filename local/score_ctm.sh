#!/bin/bash

. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: ./local/score_ctm.sh <ctm> <refdir>"
  exit 1;
fi

ctm=$1
refdir=$2

./steps/cleanup/internal/ctm_to_text.pl $ctm > `dirname $ctm`/text.hyp
utils/data/internal/combine_segments_to_recording.py \
  --write-reco2utt=${refdir}/reco2sorted_utts ${refdir}/segments ${refdir}/utt2spk
cat ${refdir}/reco2sorted_utts | ./utils/apply_map.pl -f 2- ${refdir}/text > ${refdir}/text.whole 
compute-wer --text --mode=present ark:${refdir}/text.whole ark:`dirname ${ctm}`/text.hyp

cat ${refdir}/text.whole |\
align-text --special-symbol="'***'" ark:${refdir}/text.whole ark:`dirname ${ctm}`/text.hyp ark,t:- |\
  utils/scoring/wer_per_utt_details.pl --special-symbol "'***'" |\
  tee `dirname ${ctm}`/wer_per_utt |\
  utils/scoring/wer_per_spk_details.pl ${refdir}/utt2spk \
  > `dirname ${ctm}`/wer_per_spk 
