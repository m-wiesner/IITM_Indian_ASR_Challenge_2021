#!/bin/bash
cer=false
force_rescore=false
stage=0
stop_stage=3
model_type=conformer-transformer
decoder_temperature=1
unk="<unk>"
word_unk="<unk>"
add_nlsym_whitespace=false
unk_costs="5 10 20 40 80 160 320"
acwts="1.0"
max_active=7000
beam=15
lattice_beam=8
repeat_costs="6.0 8.0 12.0"
train_lm=true
prune_beam=6
frame_splicing=1
frame_subsampling=1
model_config=model_configs/conformer_specaug_16x4x256_dec1.yaml
wip=0.0
min_lmwt=4
max_lmwt=16

source cmd.sh
source path.sh
source utils/parse_options.sh || exit 1 

if [ $# -ne 4 ]; then
  echo "Usage: $0 <exp_dir> <sp_vocab_size> <train_dir> <test_dirs>"
  echo ""
  echo "--stage <int|0>                  # stage"
  echo "--cer <bool|false>               # use CER instead of WER"
  echo "--force-rescore <bool|false>     # forces inference and scoring to run"
  exit 1
fi

exp=$1
sp_vocab_size=$2
train_dir=$3
test_dirs=$4
odir=data/lm_ctclat_${sp_vocab_size}

model=$exp/checkpoint-best.pth
actual_vocab_size=$(cat data/sp/sp_${sp_vocab_size}.vocab | wc -l )
mkdir -p $odir
# train LM
if [ $stage -le 0 ] && [ $stop_stage -ge 0 ]; then
  spm_text=$odir/input_text.encoded
  spm_vocab=data/sp/sp_${sp_vocab_size}.vocab
  words_text=$train_dir/text
  
  for f in $spm_vocab $nlsyms $words_text; do
    [ ! -f $f ] && echo "Missing required file $f" && exit 1
  done

  # encode text into spm pieces
  cat $words_text | cut -d' ' -f2- > $odir/text
  $PYTORCHSCALE2020_PYENV_ROOT/bin/python \
            $SCALE20_ROOT/pytorch-ctc/src/encode_spm.py \
            data/sp/sp_${sp_vocab_size}.model \
            $odir/text \
            $spm_text || exit 1
fi

if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  # make CTC decoding graph
  spm_text=$odir/input_text.encoded
  spm_vocab=data/sp/sp_${sp_vocab_size}.vocab
  words_text=$train_dir/text

  local/mkgraph_ctc.sh \
    --train-lm ${train_lm} \
    --unk ${unk} \
    --sos "<s>" \
    --ctc-blank "<ctc_blank>" \
    --pad "<pad>" \
    --use-sos true \
    --maps "<pad>,<eps>"\
    --repeat-costs "${repeat_costs}" \
    ${odir}/graph ${spm_vocab} ${spm_text}
fi

if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then  
  # make SPM to word transducer
  nlsyms=data/sp/nonspeech_tokens
  words_text=$train_dir/text
  
  local/make_word_fst.sh \
    --nlsyms ${nlsyms} \
    --add-nlsym-whitespace ${add_nlsym_whitespace} \
    --unk ${word_unk} \
    --unk-costs "${unk_costs}" \
    --sos "<s>" --eos "</s>" \
    ${odir}/graph/osymbols.txt ${words_text} ${odir}/graph_words
fi

if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
    for dir in $test_dirs; do
      (
      base_score_dir=$exp/score_ctclat/$(basename $dir)
      mkdir -p $base_score_dir
      echo "Decoding ${dir} on `date`"
      $train_cmd --mem 32G $base_score_dir/eval.log \
        $SCALE20_ROOT/pytorch-ctc/pytorch_wrapper.sh $PYTORCHSCALE2020_PYENV_ROOT/bin/python \
          $SCALE20_ROOT/pytorch-ctc/src/infer.py \
            --model-type $model_type \
            --frame-splicing $frame_splicing \
            --frame-subsampling $frame_subsampling \
            --kaldi-dir $dir \
            --output-posteriors $base_score_dir/logposteriors.ark \
            $model_config \
            $model \
            data/sp/sp_${sp_vocab_size}.model \
            $dir/stm \
            $base_score_dir/ctm
      
      copy-feats ark:${base_score_dir}/logposteriors.ark ark,scp:_.ark,${base_score_dir}/logposteriors.scp
      )&
    done
    wait
fi

if [ $stage -le 4 ] && [ $stop_stage -ge 4 ]; then
  for dir in $test_dirs; do
    for acwt in ${acwts}; do
      for rc in ${repeat_costs}; do
        (
        score_dir=${exp}/score_ctclat/$(basename ${dir})/acwt_${acwt}_${rc}
        base_score_dir=$exp/score_ctclat/$(basename $dir)
        post_acwt=`echo ${acwt} | awk '{print $1*10}'`
        mkdir -p ${score_dir}
        echo "Decoding posts from ${dir} acwt=${acwt} rc=${rc} ..."
        $train_cmd --mem 10G ${score_dir}/eval.log \
          $KALDI_ROOT/src/featbin/select-feats 0-${actual_vocab_size} ark:${base_score_dir}/logposteriors.ark ark:- \| \
          $KALDI_ROOT/src/bin/latgen-faster \
            --max-active=$max_active \
            --min-active=200 \
            --beam=$beam \
            --lattice-beam=$lattice_beam \
            --acoustic-scale=$acwt \
            --allow-partial=true \
            --word-symbol-table=${odir}/graph/osymbols.txt \
            ${odir}/graph/TG_${rc}.fst ark:- ark:- \| \
          $KALDI_ROOT/src/latbin/lattice-scale --acoustic-scale=${post_acwt} ark:- ark:"|gzip -c > ${score_dir}/lat.1.gz"
        
        ./local/score_text.sh --min-lmwt ${min_lmwt} \
                                --max-lmwt ${max_lmwt} \
                                --wips "0.0 0.5 1.0" \
                                --spm false \
                                --whitespace "▁" \
                                ${dir} ${odir}/graph/osymbols.txt \
                                ${score_dir}

        
        )&
      done
    done
  done
  wait
fi

if [ $stage -le 5 ] && [ $stop_stage -ge 5 ]; then
  for dir in $test_dirs; do
    for acwt in ${acwts}; do
      for rc in ${repeat_costs}; do
        for unk_cost in ${unk_costs}; do 
          (
          score_dir=${exp}/score_ctclat/$(basename ${dir})/acwt_${acwt}_${rc}
          base_score_dir=$exp/score_ctclat/$(basename $dir)
          post_acwt=`echo ${acwt} | awk '{print $1*10}'`
          mkdir -p ${score_dir}_words_${unk_cost}
          echo "Making word lattices from spm lattices ${dir} acwt=${acwt} rc=${rc} unk_cost=${unk_cost}..."
          $train_cmd --mem 10G ${score_dir}_words_${unk_cost}/eval.word.log \
            $KALDI_ROOT/src/latbin/lattice-compose ark:"gunzip -c ${score_dir}/lat.1.gz |" ${odir}/graph_words/L_spm_${unk_cost}.fst ark:- \| \
            $KALDI_ROOT/src/latbin/lattice-prune --beam=${prune_beam} ark:- ark:"|gzip -c > ${score_dir}_words_${unk_cost}/lat.1.gz"
     
          ./local/score_text.sh --min-lmwt ${min_lmwt} \
                                --max-lmwt ${max_lmwt} \
                                --wips "0.0" \
                                --spm false \
                                ${dir} ${odir}/graph_words/words.txt \
                                ${score_dir}_words_${unk_cost}
          )&
        done
      done
    done
  done
  wait
fi
