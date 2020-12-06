#!/usr/bin/env bash
#
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
LC=$SCRIPTS/tokenizer/lowercase.perl
CLEAN=$SCRIPTS/training/clean-corpus-n.perl
BPEROOT=subword-nmt
BPE_TOKENS=10000

if [ ! -d "$SCRIPTS" ]; then
    echo "Please set SCRIPTS variable correctly to point to Moses scripts."
    exit
fi

src=de
tgt=en
lang=$src-$tgt
prep=iwslt14.tokenized.$lang
tmp=$prep/tmp
orig=orig_iwslt14_$lang

URL="https://wit3.fbk.eu/archive/2014-01/texts/de/en/de-en.tgz"
GZ=$lang.tgz

mkdir -p $orig $tmp $prep

cd $orig
if [ -f $GZ ]; then
    echo "Data already downloaded."
else
    echo "Downloading data from ${URL}..."
    wget "$URL"
fi
tar zxvf $GZ
cd ..

echo "pre-processing train data..."
for l in $src $tgt; do
    f=train.tags.$lang.$l
    tok=train.tags.$lang.tok.$l

    cat $orig/$lang/$f | \
    grep -v '<url>' | \
    grep -v '<talkid>' | \
    grep -v '<keywords>' | \
    sed -e 's/<title>//g' | \
    sed -e 's/<\/title>//g' | \
    sed -e 's/<description>//g' | \
    sed -e 's/<\/description>//g' | \
    perl $TOKENIZER -threads 8 -l $l > $tmp/$tok
    echo ""
done
perl $CLEAN -ratio 1.5 $tmp/train.tags.$lang.tok $src $tgt $tmp/train.tags.$lang.clean 1 175
for l in $src $tgt; do
    perl $LC < $tmp/train.tags.$lang.clean.$l > $tmp/train.tags.$lang.$l
done

echo "pre-processing valid/test data..."
for l in $src $tgt; do
    for o in `ls $orig/$lang/IWSLT14.TED*.$l.xml`; do
    fname=${o##*/}
    f=$tmp/${fname%.*}
    echo $o $f
    grep '<seg id' $o | \
        sed -e 's/<seg id="[0-9]*">\s*//g' | \
        sed -e 's/\s*<\/seg>\s*//g' | \
        sed -e "s/\’/\'/g" | \
    perl $TOKENIZER -threads 8 -l $l | \
    perl $LC > $f
    echo ""
    done
done


echo "creating train, valid, test..."
for l in $src $tgt; do
    awk '{if (NR%23 == 0)  print $0; }' $tmp/train.tags.$lang.$l > $tmp/valid.$l
    awk '{if (NR%23 != 0)  print $0; }' $tmp/train.tags.$lang.$l > $tmp/train.$l

    cat $tmp/IWSLT14.TED.dev2010.$lang.$l \
        $tmp/IWSLT14.TEDX.dev2012.$lang.$l \
        $tmp/IWSLT14.TED.tst2010.$lang.$l \
        $tmp/IWSLT14.TED.tst2011.$lang.$l \
        $tmp/IWSLT14.TED.tst2012.$lang.$l \
        > $tmp/test.$l
done

TRAIN=$tmp/train.en-de
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
        python $BPEROOT/apply_bpe.py -c $BPE_CODE < $tmp/$f > $prep/$f
    done
done
