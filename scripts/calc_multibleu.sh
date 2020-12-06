#!/bin/bash

GEN=$1

SYS=$GEN.multi.sys
REF=$GEN.multi.ref

if [ $(tail -n 1 $GEN | grep BLEU | wc -l) -ne 1 ]; then
    echo "not done generating"
    exit
fi

grep ^H $GEN | cut -f3-  > $SYS
grep ^T $GEN | cut -f2-  > $REF
perl scripts/multi-bleu.perl  $REF < $SYS
