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

src=en
tgt=fr
lang=$src-$tgt
prep=iwslt17.tokenized.$lang
tmp=$prep/tmp
orig=orig_iwslt17_$src-$tgt

# manually download corresponding datasets from https://wit3.fbk.eu/mt.php?release=2017-01-trnted
# and https://wit3.fbk.eu/mt.php?release=2017-01-ted-test. Put the extracted files under $orig folder

mkdir -p  $tmp $prep

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
    cat $tmp/train.tags.$lang.clean.$l > $tmp/train.tags.$lang.$l
done

echo "pre-processing valid/test data..."
for l in $src $tgt; do
    for o in `ls $orig/$lang/IWSLT17.TED*.$l.xml`; do
    fname=${o##*/}
    f=$tmp/${fname%.*}
    echo $o $f
    grep '<seg id' $o | \
        sed -e 's/<seg id="[0-9]*">\s*//g' | \
        sed -e 's/\s*<\/seg>\s*//g' | \
        sed -e "s/\’/\'/g" | \
    perl $TOKENIZER -threads 8 -l $l > $f
    echo ""
    done
done


echo "creating train, valid, test..."
for l in $src $tgt; do
    cat $tmp/train.tags.$lang.$l > $tmp/train.$l

    cat $tmp/IWSLT17.TED.tst2011.$lang.$l \
        $tmp/IWSLT17.TED.tst2012.$lang.$l \
        $tmp/IWSLT17.TED.tst2013.$lang.$l \
        $tmp/IWSLT17.TED.tst2014.$lang.$l \
        $tmp/IWSLT17.TED.tst2015.$lang.$l \
        > $tmp/valid.$l

    cat $tmp/IWSLT17.TED.tst2016.$lang.$l \
        > $tmp/test.$l
    cat $tmp/IWSLT17.TED.tst2017.$lang.$l \
        >> $tmp/test.$l
done

TRAIN=$tmp/train.en-fr
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
