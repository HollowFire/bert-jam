#!/bin/bash

if [ $# -ne 3 ]; then
    echo "Error! usage: $0 SRCLANG TGTLANG GEN"
fi

SRCLANG=$1
TGTLANG=$2
GEN=$3

SCRIPTS=examples/translation/mosesdecoder/scripts
DETOKENIZER=$SCRIPTS/tokenizer/detokenizer.perl

SYS=$SAVE/gen.txt.sys.detok
REF=$SAVE/gen.txt.ref.detok

grep ^H $GEN \
| sed 's/^H\-//' \
| perl $DETOKENIZER -l $TGTLANG \
| sed "s/ - /-/g" \
> $SYS

grep ^T $GEN \
| sed 's/^T\-//' \
| perl $DETOKENIZER -l $TGTLANG \
| sed "s/ - /-/g" \
> $REF

grep ^H $GEN | cut -f3- | perl $DETOKENIZER -l $TGTLANG \ | sed "s/ - /-/g" > $SYS
grep ^T $GEN | cut -f2- | perl $DETOKENIZER -l $TGTLANG \ | sed "s/ - /-/g" > $REF

cat $SYS | sacrebleu $REF --language-pair "${SRCLANG}-${TGTLANG}"
