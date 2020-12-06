#!/bin/bash
# Adapted from https://github.com/facebookresearch/MIXER/blob/master/prepareData.sh

if [ ! -d "mosesdecoder" ]; then
    echo 'Cloning Moses github repository (for tokenization scripts)...'
    git clone https://github.com/moses-smt/mosesdecoder.git
fi

if [ ! -d "subword-nmt" ]; then
    echo 'Cloning Subword NMT repository (for BPE pre-processing)...'
    git clone https://github.com/rsennrich/subword-nmt.git
fi


SCRIPTS=mosesdecoder/scripts
TOKENIZER=$SCRIPTS/tokenizer/tokenizer.perl
CLEAN=$SCRIPTS/training/clean-corpus-n.perl
NORM_PUNC=$SCRIPTS/tokenizer/normalize-punctuation.perl
REM_NON_PRINT_CHAR=$SCRIPTS/tokenizer/remove-non-printing-char.perl
BPEROOT=subword-nmt
BPE_TOKENS=32000

URLS=(
    "http://data.statmt.org/wmt16/translation-task/training-parallel-ep-v8.tgz"
    "http://data.statmt.org/rsennrich/wmt16_backtranslations/en-ro/corpus.bt.en-ro.en.gz"
    "http://data.statmt.org/rsennrich/wmt16_backtranslations/en-ro/corpus.bt.en-ro.ro.gz"
    "https://object.pouta.csc.fi/OPUS-SETIMES/v2/moses/en-ro.txt.zip"
    "http://data.statmt.org/wmt16/translation-task/dev-romanian-updated.tgz"
    "http://data.statmt.org/wmt16/translation-task/test.tgz"
)
FILES=(
    "training-parallel-ep-v8.tgz"
    "corpus.bt.en-ro.en.gz"
    "corpus.bt.en-ro.ro.gz"
    "en-ro.txt.zip"
    "dev-romanian-updated.tgz"
    "test.tgz"
)
CORPORA=(
    "training-parallel-ep-v8/europarl-v8.ro-en"
    "corpus.bt.en-ro"
    "SETIMES.en-ro"
)

if [ ! -d "$SCRIPTS" ]; then
    echo "Please set SCRIPTS variable correctly to point to Moses scripts."
    exit
fi

src=en
tgt=ro
lang=en-ro
prep=wmt16_en_ro_32k
tmp=$prep/tmp
orig=orig_wmt16_$lang


mkdir -p $orig $tmp $prep

:<<!
cd $orig

for ((i=0;i<${#URLS[@]};++i)); do
    file=${FILES[i]}
    if [ -f $file ]; then
        echo "$file already exists, skipping download"
    else
        url=${URLS[i]}
        wget "$url"
        if [ -f $file ]; then
            echo "$url successfully downloaded."
        else
            echo "$url not successfully downloaded."
            exit -1
        fi
    fi
    if [ ${file: -4} == ".tgz" ]; then
        tar zxvf $file
    elif [ ${file: -4} == ".zip" ]; then
        unzip $file
    fi

done

gunzip corpus.bt.en-ro.en.gz
gunzip corpus.bt.en-ro.ro.gz
cd ..
!

echo "pre-processing train data..."
for l in $src $tgt; do
    rm $tmp/train.tags.$lang.tok.$l
    for f in "${CORPORA[@]}"; do
        cat $orig/$f.$l | \
            perl $NORM_PUNC $l | \
            perl $REM_NON_PRINT_CHAR | \
            perl $TOKENIZER -threads 8 -a -l $l >> $tmp/train.tags.$lang.tok.$l
    done
done

echo "pre-processing test data..."
for l in $src $tgt; do
    if [ "$l" == "$src" ]; then
        t="src"
    else
        t="ref"
    fi
    grep '<seg id' $orig/test/newstest2016-enro-$t.$l.sgm | \
        sed -e 's/<seg id="[0-9]*">\s*//g' | \
        sed -e 's/\s*<\/seg>\s*//g' | \
        sed -e "s/\’/\'/g" | \
    perl $TOKENIZER -threads 8 -a -l $l > $tmp/test.$l

    grep '<seg id' $orig/dev/newsdev2016-enro-$t.$l.sgm | \
        sed -e 's/<seg id="[0-9]*">\s*//g' | \
        sed -e 's/\s*<\/seg>\s*//g' | \
        sed -e "s/\’/\'/g" | \
    perl $TOKENIZER -threads 8 -a -l $l > $tmp/valid.$l

    echo ""
done


for l in $src $tgt; do
#    awk '{if (NR%1333 == 0)  print $0; }' $tmp/train.tags.$lang.tok.$l > $tmp/valid.$l
#    awk '{if (NR%1333 != 0)  print $0; }' $tmp/train.tags.$lang.tok.$l > $tmp/train.$l
    cat $tmp/train.tags.$lang.tok.$l > $tmp/train.$l
done

TRAIN=$tmp/train.ro-en
BPE_CODE=$prep/code
rm -f $TRAIN
for l in $src $tgt; do
    cat $tmp/train.$l >> $TRAIN
done

echo "learn_bpe.py on ${TRAIN}..."
python $BPEROOT/learn_bpe.py -s $BPE_TOKENS < $TRAIN > $BPE_CODE

for L in $src $tgt; do
    for f in train.$L valid.$L test.$L; do
        echo "apply_bpe.py to ${f}..."
        python $BPEROOT/apply_bpe.py -c $BPE_CODE < $tmp/$f > $tmp/bpe.$f
    done
done

perl $CLEAN -ratio 1.5 $tmp/bpe.train $src $tgt $prep/train 1 250
perl $CLEAN -ratio 1.5 $tmp/bpe.valid $src $tgt $prep/valid 1 250

for L in $src $tgt; do
    cp $tmp/bpe.test.$L $prep/test.$L
done
