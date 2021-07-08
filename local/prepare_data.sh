#!/bin/bash
. ./path.sh
. ./cmd.sh

max_dups=10

. ./utils/parse_options.sh

ROOT=$1 #/export/common/data/corpora/ASR/IITM_Indian_ASR_Challenge_2021/Indian_Language_Database
language=$2

mkdir -p data
cd data
cp -r ${ROOT}/${language}/transcription/{train,dev}_${language} .
cd ..
for d in train dev; do
  mv data/${d}_${language}/wav.scp data/${d}_${language}/wav.scp.bk && \
    awk -v var=${ROOT}/${language} '{print $1,var"/"$2}' data/${d}_${language}/wav.scp.bk \
    > data/${d}_${language}/wav.scp
  sed 's/\t */ /' data/${d}_${language}/text > data/${d}_${language}/text.tmp
  awk '(NF > 1)' data/${d}_${language}/text.tmp > data/${d}_${language}/text
  ./utils/fix_data_dir.sh data/${d}_${language}
done

./utils/combine_data.sh data/all_${language} data/{train,dev}_${language}

# 0.6 seemed to be a good value. Look at the histogram dumped into the datadir
local/rename_long_recordings.py --plot --sim-thresh 0.6 data/all_${language}
local/create_devset.py data/all_${language} data/local/dev_splits

# For end-to-end systems I think we care more about the ho prompts. Therefore,
# we use the heldout prompts as the dev set.
./utils/copy_data_dir.sh data/all_${language} data/dev_${language}_jhu
./utils/copy_data_dir.sh data/all_${language} data/train_${language}_jhu
./utils/filter_scp.pl -f 1 data/local/dev_splits/ho_prompts \
  data/all_${language}/wav.scp > data/dev_${language}_jhu/wav.scp
./utils/filter_scp.pl --exclude -f 1 data/local/dev_splits/ho_prompts \
  data/all_${language}/wav.scp > data/train_${language}_jhu/wav.scp
./utils/fix_data_dir.sh data/train_${language}_jhu 
./utils/fix_data_dir.sh data/dev_${language}_jhu

./utils/data/remove_dup_utts.sh ${max_dups} data/train_${language}_jhu data/train_${language}_jhu_nodup
for d in train_${language}_jhu train_${language}_jhu_nodup dev_${language}_jhu; do
  hrs=`awk '{sum+=$4-$3} END{print sum/3600}' data/${d}/segments`
  echo "${d} -- ${hrs} hr of speech"
done

hrs=`awk '(NR==FNR){a[$1]=1} ($2 in a){sum+=$4-$3} END{print sum/3600}' data/local/dev_splits/ho_spk_and_prompt data/dev_${language}_jhu/segments`
echo "The ho_spk_and_prompt set has ${hrs} hr of speech"
