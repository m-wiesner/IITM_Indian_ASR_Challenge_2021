#!/bin/bash
. ./path.sh
. ./cmd.sh

max_dups=10
hybrid=false

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

# Create the actual dev set we most care about (ho speaker and text)
./utils/copy_data_dir.sh data/dev_${language}_jhu data/dev_${language}_jhu_ho_spk
./utils/filter_scp.pl -f 1 data/local/dev_splits/ho_spk_and_prompt data/dev_${language}_jhu/wav.scp > data/dev_${language}_jhu_ho_spk/wav.scp
./utils/fix_data_dir.sh data/dev_${language}_jhu_ho_spk 

./utils/copy_data_dir.sh data/all_${language} data/train_${language}_jhu_hybrid
./utils/filter_scp.pl --exclude -f 1 data/dev_${language}_jhu_ho_spk/wav.scp data/all_${language}/wav.scp > data/train_${language}_jhu_hybrid/wav.scp
./utils/fix_data_dir.sh data/train_${language}_jhu_hybrid

# For eval we can only use the train data and the jhu set has some dev in it.
# We use the intersection of the train sets as the training set, and the 
# left-over part as the dev set.
./utils/copy_data_dir.sh data/train_${language}_jhu data/train_${language}_intersect_jhu
cp data/train_${language}/text data/train_${language}_intersect_jhu
./utils/fix_data_dir.sh data/train_${language}_intersect_jhu
./utils/copy_data_dir.sh data/train_${language}_jhu data/train_dev_${language}_jhu
./utils/filter_scp.pl --exclude -f 1 data/train_${language}_intersect_jhu/text data/train_${language}_jhu/text > data/train_dev_${language}_jhu/text
./utils/fix_data_dir.sh data/train_dev_${language}_jhu

./utils/copy_data_dir.sh data/train_${language}_jhu_hybrid data/train_${language}_intersect_jhu_hybrid
cp data/train_${language}/text data/train_${language}_intersect_jhu_hybrid
./utils/fix_data_dir.sh data/train_${language}_intersect_jhu_hybrid
./utils/copy_data_dir.sh data/train_${language}_jhu_hybrid data/train_dev_${language}_jhu_hybrid
./utils/filter_scp.pl --exclude -f 1 data/train_${language}_intersect_jhu_hybrid/text data/train_${language}_jhu_hybrid/text > data/train_dev_${language}_jhu_hybrid/text
./utils/fix_data_dir.sh data/train_dev_${language}_jhu_hybrid


./utils/data/remove_dup_utts.sh ${max_dups} data/train_${language}_intersect_jhu data/train_${language}_final
./utils/data/remove_dup_utts.sh ${max_dups} data/train_${language}_intersect_jhu_hybrid data/train_${language}_final_hybrid
for d in train_${language} train_${language}_jhu_hybrid train_${language}_jhu train_${language}_intersect_jhu train_${language}_intersect_jhu_hybrid train_${language}_final train_${language}_final_hybrid train_dev_${language}_jhu train_dev_${language}_jhu_hybrid dev_${language}_jhu dev_${language}_jhu_ho_spk; do
  hrs=`awk '{sum+=$4-$3} END{print sum/3600}' data/${d}/segments`
  echo "${d} -- ${hrs} hr of speech"
done
