#!/bin/bash

. ./path.sh
. ./cmd.sh

data_root=/export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database
lang=English
stage=0
stop_stage=0
nj=200
subsampling=4
num_leaves=3500

. ./utils/parse_options.sh

# Setup data dirs
if [ $stage -le 0 ] && [ $stop_stage -ge 0 ]; then
  ./local/prepare_data.sh ${data_root} ${lang}
fi

# Set langdir
if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  ./local/prepare_dict.sh ${data_root} ${lang} data/dict_${lang}_nosp
  ./utils/prepare_lang.sh --share-silence-phones true \
    data/dict_${lang}_nosp "<unk>" data/dict_${lang}_nosp/tmp.lang data/lang_${lang}_nosp 
fi

# Make features
if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then
  for x in train_${lang}_nodup dev_${lang}_dup dev_${lang}_nodup; do
    ./steps/make_mfcc.sh --nj "$nj" --cmd "$train_cmd" data/$x exp/make_mfcc/$x mfcc
    ./steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x mfcc
    ./utils/fix_data_dir.sh data/${x}
  done
  
  ./utils/subset_data_dir.sh --shortest data/train_${lang}_nodup 500 data/train_${lang}_nodup_500short
  ./utils/subset_data_dir.sh data/train_${lang}_nodup 5000 data/train_${lang}_nodup_5k
  ./utils/subset_data_dir.sh data/train_${lang}_nodup 10000 data/train_${lang}_nodup_10k
fi

datadir=data/train_${lang}_nodup
langdir=data/lang_${lang}_nosp

# Monophone system
if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  echo "Monophone training ..."
  affix=_500short
  ./steps/train_mono.sh --nj 50 --cmd "$train_cmd" \
    ${datadir}${affix} ${langdir} exp/mono_${lang}
fi

if [ $stage -le 4 ] && [ $stop_stage -ge 4 ]; then
  echo "Tri1a training ..."
  affix=_5k
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
   ${datadir}${affix} ${langdir} exp/mono_${lang} exp/mono_${lang}_ali${affix}
  steps/train_deltas.sh --boost-silence 1.25  --cmd "$train_cmd"  \
    2000 10000 ${datadir}${affix} ${langdir} exp/mono_${lang}_ali${affix} exp/tri1a_${lang}
fi

if [ $stage -le 5 ] && [ $stop_stage -ge 5 ]; then
  echo "Tri1b training ..."
  affix=_10k
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    ${datadir}${affix} ${langdir} exp/tri1a_${lang} exp/tri1a_${lang}_ali_train${affix}

  steps/train_deltas.sh --boost-silence 1.25  --cmd "$train_cmd"  \
    2500 15000 ${datadir}${affix} ${langdir} exp/tri1a_${lang}_ali_train${affix} exp/tri1b_${lang}
fi

if [ $stage -le 6 ] && [ $stop_stage -ge 6 ]; then
  echo "Tri2 training ..."
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    ${datadir} ${langdir} exp/tri1b_${lang} exp/tri1b_${lang}_ali_train

  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" 4200 40000 \
        ${datadir} ${langdir} exp/tri1b_${lang}_ali_train exp/tri2_${lang}
fi

if [ $stage -le 7 ] && [ $stop_stage -ge 7 ]; then
  echo "Tri3 training ..."
  steps/align_si.sh --use-graphs true --nj $nj --cmd "$train_cmd" \
    ${datadir} ${langdir} exp/tri2_${lang} exp/tri2_${lang}_ali_train

  steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
    ${datadir} ${langdir} exp/tri2_${lang}_ali_train exp/tri3_${lang}
fi

if [ $stage -le 8 ] && [ $stop_stage -ge 8 ]; then
  echo "Learning pron probs in lexicon and aligning ..."
  ./steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    ${datadir} ${langdir} exp/tri3_${lang} exp/tri3_${lang}_ali_train
  steps/get_prons.sh --cmd "$train_cmd" \
    ${datadir} ${langdir} exp/tri3_${lang}_ali_train
  utils/dict_dir_add_pronprobs.sh --max-normalize true \
    data/dict_${lang}_nosp \
    exp/tri3_${lang}_ali_train/pron_counts_nowb.txt \
    exp/tri3_${lang}_ali_train/sil_counts_nowb.txt \
    exp/tri3_${lang}_ali_train/pron_bigram_counts_nowb.txt \
    data/dict_${lang}

  utils/prepare_lang.sh --share-silence-phones true data/dict_${lang} \
    "<unk>" data/dict_${lang}/.lang_tmp data/lang_${lang}
fi

if [ $stage -le 9 ] && [ $stop_stage -ge 9 ]; then
  echo "Perturb data speed 3 way ..."
  ./utils/data/perturb_data_dir_speed_3way.sh ${datadir}_nodev ${datadir}_nodev_sp
  ./steps/make_mfcc.sh --nj "$nj" --cmd "$train_cmd" ${datadir}_nodev_sp exp/make_mfcc/train_${lang}_nodup_nodev_sp mfcc
  ./steps/compute_cmvn_stats.sh ${datadir}_nodev_sp exp/make_mfcc/train_${lang}_nodup_nodev_sp mfcc
  ./utils/fix_data_dir.sh ${datadir}_nodev_sp
fi

if [ $stage -le 10 ] && [ $stop_stage -ge 10 ]; then
  echo "Aligning speed perturbed data ..."
  ./steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    ${datadir}_nodev_sp data/lang_${lang} exp/tri3_${lang} exp/tri3_${lang}_ali_nodev_sp 
fi

if [ $stage -le 11 ] && [ $stop_stage -ge 11 ]; then
  echo "Making chain dir ..."
  ./local/make_chain.sh --subsampling ${subsampling} \
                        --num-leaves ${num_leaves} \
                        ${datadir}_nodev_sp data/lang_${lang} \
                        exp/tri3_${lang}_ali_nodev_sp exp/chain_${subsampling}
fi

if [ $stage -le 12 ] && [ $stop_stage -ge 12 ]; then
  echo "Making feats and target for nnet_pytorch training"
  #./utils/copy_data_dir.sh ${datadir}_nodev_sp ${datadir}_nodev_sp_fbank_64
  #./steps/make_fbank.sh --cmd "$train_cmd" --nj $nj ${datadir}_nodev_sp_fbank_64 exp/make_fbank/train_${lang}_nodup_nodev_sp_fbank fbank
  ./steps/compute_cmvn_stats.sh ${datadir}_nodev_sp_fbank_64
  ./utils/fix_data_dir.sh ${datadir}_nodev_sp_fbank_64
  ali-to-pdf exp/chain_${subsampling}/tree/final.mdl ark:"gunzip exp/chain_${subsampling}/tree/ali.*.gz |" ark,t:${datadir}_nodev_sp_fbank_64/pdfid.${subsampling}.tgt
  split_memmap_data.sh ${datadir}_nodev_sp_fbank_64 ${datadir}_nodev_sp_fbank_64/pdfid.4.tgt 80 
fi
