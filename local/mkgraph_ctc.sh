#!/bin/bash
# Copyright 2020 Matthew Wiesner 
# Apache 2.0

# This script creates a fully expanded decoding graph (HCLG) that represents
# all the language-model, pronunciation dictionary (lexicon), context-dependency,
# and HMM structure in our model.  The output is a Finite State Transducer
# that has word-ids on the output, and pdf-ids on the input (these are indexes
# that resolve to Gaussian Mixture Models).
# See
#  http://kaldi-asr.org/doc/graph_recipe_test.html
# (this is compiled from this repository using Doxygen,
# the source for this part is in src/doc/graph_recipe_test.dox)

set -o pipefail

unk="[unknown]"
sos="<s>"
ctc_blank="<ctc_blank>"
pad="<pad>"
use_sos=false
maps="<pad>,<eps> <unk>,[unknown]" 
ngram_order=4
repeat_costs="0.5 1.0 2.0"
train_lm=true

. ./utils/parse_options.sh
if [ $# -ne 3 ]; then
  echo "Usage: ./local/mkgraph_ctc.sh <odir> <vocab> <train_text>"
  echo "  vocab should be a file of symbols produced by the neural network in"
  echo "  the exact order used in the neural network. A few special control"
  echo "  symbols are defined: start-of-sequence <s>, end-of-sequence </s>,"
  echo "  unknown <unk> or [unknown], and ctc_blank <ctc_blank>. We assume"
  echo "  </s>, <ctc_blank>, and at least 1 unk symbol exist. <ctc_blank> is"
  echo "  assumed to be the last symbol in the vocab."   
  exit 1;
fi

lmdir=$1
vocab=$2
train=$3

mkdir -p ${lmdir}
unset LC_ALL
# Create vocab. 
awk -v ctc=${ctc_blank} 'BEGIN{print "<eps> 0"} {print $1" "NR} END{print ctc" "NR+1}' ${vocab} \
  > ${lmdir}/isymbols.txt

for i in $maps; do echo ${i%%,*}; done > ${lmdir}/remove_from_osymbols.txt

# Some systems don't use a <s> symbol, but we need it for compatibility with
# the language model.
if $use_sos; then
  grep -vF "${ctc_blank}" ${lmdir}/isymbols.txt | grep -vFf ${lmdir}/remove_from_osymbols.txt |\
    grep -vF "<eps>" | awk 'BEGIN{print "<eps> 0"} {print $1" "NR}' > ${lmdir}/osymbols.txt
else
  grep -vF ${ctc_blank} ${lmdir}/isymbols.txt | grep -vFf ${lmdir}/remove_from_osymbols.txt |\
    grep -vF "<eps>" | awk -v sos=${sos} 'BEGIN{print "<eps> 0"} {print $1" "NR} END{print sos" "NR+1}'\
    > ${lmdir}/osymbols.txt
fi

# Train language model
if $train_lm; then
  ngram-count -lm ${lmdir}/lm.gz -gt1min 0 -gt2min 1 -gt3min 1 -gt4min 2 -gt5min 2 -gt6min 2 -order 6 \
    -text ${train} -vocab <(grep -v '<eps>' ${lmdir}/osymbols.txt | grep -vF "${unk}") \
    -unk -sort -map-unk "${unk}"
  
  gunzip -c ${lmdir}/lm.gz |\
     arpa2fst --read-symbol-table=${lmdir}/osymbols.txt - ${lmdir}/G.fst
fi

for rc in ${repeat_costs}; do
  python local/make-h-transducer.py \
    --maps "${maps}" \
    --ctc-blank ${ctc_blank} \
    --sos ${sos} \
    --repeat-cost ${rc} \
    ${lmdir}/{i,o}symbols.txt ${lmdir}/T_${rc}.fst
done

export LC_ALL=C
for rc in ${repeat_costs}; do
  fsttablecompose ${lmdir}/T_${rc}.fst ${lmdir}/G.fst |\
    fstrmepslocal | fstminimizeencoded > ${lmdir}/TG_${rc}.fst
done
