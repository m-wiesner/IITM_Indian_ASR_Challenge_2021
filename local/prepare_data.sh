#!/bin/bash
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
  ./utils/data/remove_dup_utts.sh 10 data/train_${language} data/train_${language}_nodup
  ./utils/subset_data_dir.sh --speakers data/train_${language}_nodup 2000 data/train_dev_${language} 
  ./utils/copy_data_dir.sh data/train_${language}_nodup{,_nodev}
  cat data/train_dev_${language}/segments |\
    ./utils/filter_scp.pl -f 1 --exclude - data/train_${language}_nodup/segments \
    > data/train_${language}_nodup_nodev/segments
  ./utils/fix_data_dir.sh data/train_${language}_nodup_nodev
done

# Dev data
./local/identify_seen_utts.pl data/train_${language}/text data/dev_${language}/text |\
  ./local/identify_seen_convs.pl |\
  awk '($2<80){print $1}' > data/dev_${language}/convs_nodup
./local/identify_seen_utts.pl data/train_${language}/text data/dev_${language}/text |\
  ./local/identify_seen_convs.pl |\
  awk '($2>=80){print $1}' > data/dev_${language}/convs_dup

./utils/copy_data_dir.sh data/dev_${language} data/dev_${language}_nodup
./utils/copy_data_dir.sh data/dev_${language} data/dev_${language}_dup 
awk '(NR==FNR){a[$1]=1;next} ($2 in a){print $0}' data/dev_${language}/convs_nodup data/dev_${language}/segments > data/dev_${language}_nodup/segments
awk '(NR==FNR){a[$1]=1;next} ($2 in a){print $0}' data/dev_${language}/convs_dup data/dev_${language}/segments > data/dev_${language}_dup/segments

./utils/fix_data_dir.sh data/dev_${language}_nodup
./utils/fix_data_dir.sh data/dev_${language}_dup
