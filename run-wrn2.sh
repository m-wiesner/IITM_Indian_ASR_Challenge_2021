#!/bin/bash

# This is based almost entirely on the Kaldi librispeech recipe
# Change this location to somewhere where you want to put the data.
# This recipe ASSUMES YOU HAVE DOWNLOADED the Librispeech data
unlabeled_data=/export/corpora5 #/PATH/TO/LIBRISPEECH/data

. ./cmd.sh
. ./path.sh

subsampling=4
traindir=data/train_English_nodup_nodev_sp
feat_affix=
chaindir=exp/chain_wrn
model_dirname=wrn_lfmmi
width=10
depth=28
l2=0.0001
xent=0.2
infonce=0.0
lr=0.001
leaky_hmm=0.1
decay=1e-05
weight_decay=1e-07
warmup=15000
batches_per_epoch=250
num_epochs=240
nj_init=2
nj_final=2
perturb="[('time_mask', {'width': 10, 'max_drop_percent': 0.5}), ('freq_mask', {'width': 10, 'holes': 5}), ('gauss', {'std': 0.1})]"
chunkwidth=220
min_chunkwidth=60
random_cw=True
left_context=10
right_context=5
batchsize=24
delay_updates=1
grad_thresh=32.0
seed=0
resume=
init=
num_split=80 # number of splits for memory-mapped data for training
. ./utils/parse_options.sh

set -euo pipefail

tree=${chaindir}/tree
targets=${traindir}${feat_affix}/pdfid.${subsampling}.tgt
trainname=`basename ${traindir}`

resume_opts=
if [ ! -z $resume ]; then
  resume_opts="--resume ${resume}"
fi 

num_pdfs=$(tree-info ${tree}/tree | grep 'num-pdfs' | cut -d' ' -f2)
train_script="train.py ${resume_opts} \
  --gpu \
  --expdir `dirname ${chaindir}`/${model_dirname} \
  --objective  Multitask \
  --multitask-losses \"[('LFMMIOnly', 1.0, 0), ('CrossEntropy', ${xent}, 1), ('L2', ${l2}, 0)]\" \
  --denom-graph ${chaindir}/den.fst \
  --leaky-hmm ${leaky_hmm} \
  --num-targets ${num_pdfs} \
  --subsample ${subsampling} \
  --model ChainWideResnet \
  --strides \"${strides}\" \
  --depth ${depth} \
  --width ${width} \
  --warmup ${warmup} \
  --decay ${decay} \
  --weight-decay ${weight_decay} \
  --lr ${lr} \
  --optim adam \
  --batches-per-epoch ${batches_per_epoch} \
  --num-epochs 1 \
  --delay-updates ${delay_updates} \
  --grad-thresh ${grad_thresh} \
  --datasets \"[ \
      {\
   'data': '${traindir}${feat_affix}', \
   'tgt': '${targets}', \
   'batchsize': ${batchsize}, \
   'chunk_width': ${chunkwidth}, 'min_chunk_width': ${min_chunkwidth}, \
   'left_context': ${left_context}, 'right_context': ${right_context}, 'num_repeats': 1, \
   'mean_norm': True, 'var_norm': False, 'random_cw': ${random_cw}, 'cw_curriculum': 0.0, \
   'perturb_type': '''${perturb}'''\
     },\
   ]\"\
   "

train_cmd="utils/retry.pl utils/queue.pl --mem 12G --gpu 1 --config conf/gpu.conf"

train_async_parallel.sh ${resume_opts} \
  --cmd "$train_cmd" \
  --nj-init ${nj_init} \
  --nj-final ${nj_final} \
  --num-epochs ${num_epochs} \
  --seed ${seed} \
  "${train_script}" `dirname ${chaindir}`/${model_dirname}


