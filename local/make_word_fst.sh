#!/bin/bash

. ./path.sh
. ./cmd.sh

nlsyms=data/lang/non_lang_syms.txt
whitespace_symbol="#"
add_nlsym_whitespace=true
unk="[unknown]"
unk_costs="4"
sos="<s>"
eos="</s>"
. ./utils/parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: ./local/make_word_fst.sh <spm> <text> <odir>"
  exit 1;
fi

spm=$1
text=$2
odir=$3

mkdir -p ${odir}

spm_opts=""
if $add_nlsym_whitespace; then
  spm_opts="--add-nlsym-whitespace"
fi

# Do word fst first
cut -d' ' -f2- ${text} | LC_ALL= tr " " "\n" | LC_ALL=C sort -u > ${odir}/words

grep -vFf ${nlsyms} ${odir}/words | paste -d' ' - <(LC_ALL= grep -vFf ${nlsyms} ${odir}/words | LC_ALL= sed 's/./& /g') |\
  cat <(paste -d' ' <(LC_ALL= grep -Ff ${nlsyms} ${odir}/words) \
      <(LC_ALL= grep -Ff ${nlsyms} ${odir}/words)) - |\
  awk -v ws=${whitespace_symbol} '{print ws $0}' > ${odir}/lexicon.txt

cut -d' ' -f2- ${odir}/lexicon.txt | tr " " "\n" |\
  LC_ALL=C sort -u | LC_ALL= grep -v '^\s*$' |\
  awk -v ws=${whitespace_symbol} '
    BEGIN {print "<eps> 0"} 
    {print $1" "NR} 
    END {print ws" "NR+1}' \
  > ${odir}/graphemes.txt

awk -v unk=${unk} -v ws=${whitespace_symbol} 'BEGIN{print "<eps> 0"; print unk" 1"} (NR==FNR){print ws $1" "NR+1; next} (NR>FNR){print $1" "NR+1}' ${odir}/words <(grep -v '<eps>' ${odir}/graphemes.txt) > ${odir}/words.txt
for unk_cost in ${unk_costs}; do
  echo "Making word fst with unk_cost=${unk_cost} ..."
  local/make_word_fst.py \
    --whitespace "${whitespace_symbol}" \
    --unk "${unk}" \
    --unk-cost ${unk_cost} \
    --nlsyms ${nlsyms} \
    ${odir}/words.txt ${odir}/graphemes.txt \
    ${odir}/lexicon.txt ${odir}/L_tmp_${unk_cost}.fst
done

for unk_cost in ${unk_costs}; do
  echo "Closure, inverting, and minimizing L_tmp_${unk_cost}.fst"
  fstclosure ${odir}/L_tmp_${unk_cost}.fst | fstinvert | \
    fstrmepslocal | fstminimize --allow_nondet=true | \
    fstrmepslocal | fstarcsort --sort_type=ilabel \
    > ${odir}/L_${unk_cost}.fst
done

# Do spm fst
LC_ALL= python local/make_spm_fst.py ${spm_opts} \
  --nlsyms ${nlsyms} \
  --replace-whitespace-symbol ${whitespace_symbol} \
  --sos ${sos} \
  --eos ${eos} \
  ${spm} ${odir}/graphemes.txt ${odir}/SPM_tmp.fst

fstclosure ${odir}/SPM_tmp.fst | fstrmepslocal |\
  fstminimize --allow_nondet=true | fstrmepslocal |\
  fstarcsort --sort_type=olabel > ${odir}/SPM.fst

# Compose them
(
  for unk_cost in ${unk_costs}; do
    echo "Composing SPM.fst L_${unk_cost}.fst"
    $train_cmd ${odir}/compose.${unk_cost}.log \
      fsttablecompose ${odir}/SPM.fst ${odir}/L_${unk_cost}.fst \| \
        fstminimize --allow_nondet=true \| \
        fstrmepslocal '>' ${odir}/L_spm_${unk_cost}.fst || touch ${odir}/.error &
  done
  wait
)

[ -f ${odir}/.error ] && echo "$0: error in composing fsts" && exit 1;

