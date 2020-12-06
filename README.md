# Introduction
This repository contains the code for BERT-JAM, which is adapted from the [bertnmt](https://github.com/bert-nmt/bert-nmt) repository.

# Requirements and Installation

* [PyTorch](http://pytorch.org/) version: 1.2
* Python version: 3.7
* Versions of other packages are shown in the version.txt file

**Installing from source**

To install fairseq from source and develop locally:
```
cd bertnmt
pip install --editable .
```

# Getting Started
### Data Preparation
First, download the bert model files and put them under the ./pretrained directory. The folder structure should look like this:
```
bertnmt
|---bert
|---data-bin
|---docs
|---examples
|---fairseq
|---fairseq-cli
|---my
|---pretrained
|   |---bert-base-german-uncased
|   |   |---config.json
|   |   |---pytorch_model.bin
|   |   |---vocab.txt
|---save
|---scripts
|---test
```
The scripts for pre-precessing the data are under the ./examples/translation/script/ directory. For example, run the following code to pre-process the iwslt'14 De_En data.
```
cd ./examples/translation/
bash script/prepare-iwslt14.de2en.sh
cd iwslt14.tokenized.de-en
bash ../script/makedataforbert.sh de
```
Then preprocess data as in Fairseq:
```
src=de
tgt=en
TEXT=examples/translation/iwslt14.tokenized.de-en
python preprocess.py --source-lang $src --target-lang $tgt \
  --trainpref $TEXT/train --validpref $TEXT/valid --testpref $TEXT/test \
  --destdir $DATADIR/iwslt14_de_en/  --joined-dictionary \
  --bert-model-name pretrained/bert-base-german-uncased
```
### Training
The model is trained following the three-phase optimization strategy. 
Use the fairseq scripts the train the model. The following scripts show how to train the model for the iwslt14 De-En dataset. For the first phase: 
```
BERT=bert-base-german-uncased
src=de
tgt=en
model=bt_glu_joint
ARCH=${model}_iwslt_de_en
DATAPATH=data-bin/iwslt14.tokenized.$src-$tgt
SAVE=save/${model}.iwslt14.$src-$tgt.$BERT.
mkdir -p $SAVE
python train.py $DATAPATH \
-a $ARCH --optimizer adam --lr 0.0005 -s $src -t $tgt --label-smoothing 0.1 \
--dropout 0.3 --max-tokens 4000 --min-lr '1e-09' --lr-scheduler inverse_sqrt --weight-decay 0.0001 \
--criterion label_smoothed_cross_entropy --warmup-updates 4000 --warmup-init-lr '1e-07' --keep-last-epochs 10 \
--adam-betas '(0.9,0.98)' --save-dir $SAVE --share-all-embeddings   \
--encoder-bert-dropout --encoder-bert-dropout-ratio 0.5 \
--bert-model-name pretrained/$BERT \
--user-dir my --no-progress-bar --max-epoch 40 --fp16 \
--ddp-backend=no_c10d \
| tee -a $SAVE/training.log
```
For the second phase:
```
cp $SAVE/checkpoint_last.pt $SAVE/checkpoint_nmt.pt
python train.py $DATAPATH \
-a $ARCH --optimizer adam --lr 0.0005 -s $src -t $tgt --label-smoothing 0.1 \
--dropout 0.3 --max-tokens 4000 --min-lr '1e-09' --lr-scheduler inverse_sqrt --weight-decay 0.0001 \
--criterion label_smoothed_cross_entropy --warmup-updates 4000 --warmup-init-lr '1e-07' --keep-last-epochs 10 \
--adam-betas '(0.9,0.98)' --save-dir $SAVE --share-all-embeddings   \
--encoder-bert-dropout --encoder-bert-dropout-ratio 0.5 \
--bert-model-name pretrained/$BERT \
--user-dir my --no-progress-bar --max-epoch 50 --fp16 \
--ddp-backend=no_c10d \
--adjust-layer-weights \
--warmup-from-nmt \
| tee -a $SAVE/adjust.log
```
For the third phase:
```
cp $SAVE/checkpoint_last.pt $SAVE/checkpoint_nmt.pt
python train.py $DATAPATH \
-a $ARCH --optimizer adam --lr 0.0005 -s $src -t $tgt --label-smoothing 0.1 \
--dropout 0.3 --max-tokens 4000 --min-lr '1e-09' --lr-scheduler inverse_sqrt --weight-decay 0.0001 \
--criterion label_smoothed_cross_entropy --warmup-updates 4000 --warmup-init-lr '1e-07' --keep-last-epochs 10 \
--adam-betas '(0.9,0.98)' --save-dir $SAVE --share-all-embeddings   \
--encoder-bert-dropout --encoder-bert-dropout-ratio 0.5 \
--bert-model-name pretrained/$BERT \
--user-dir my --no-progress-bar --max-epoch 60 --fp16 \
--ddp-backend=no_c10d \
--adjust-layer-weights \
--finetune-bert \
--warmup-from-nmt \
| tee -a $SAVE/finetune.log
```

### Generation
Generate on the test data split using the fairseq script. For the tasks that report tokenized BLEU scores:
```
python scripts/average_checkpoints.py --inputs $SAVE \
    --num-epoch-checkpoints 10 --output "${SAVE}/checkpoint_last10_avg.pt"

CUDA_VISIBLE_DEVICES=0 fairseq-generate $DATAPATH \
    --path "${SAVE}/checkpoint_last10_avg.pt" --batch-size 64 --beam 5 --remove-bpe \
    --lenpen 1 --gen-subset test --quiet --user-dir my  \
    --bert-model-name pretrained/$BERT
```
For the tasks that report sacreBLEU scores:
```
python scripts/average_checkpoints.py --inputs $SAVE \
    --num-epoch-checkpoints 10 --output "${SAVE}/checkpoint_last10_avg.pt"

CUDA_VISIBLE_DEVICES=0 fairseq-generate $DATAPATH \
    --path "${SAVE}/checkpoint_last10_avg.pt" --batch-size 64 --beam 5 --remove-bpe \
    --lenpen 1 --gen-subset test --user-dir my  \
    --bert-model-name pretrained/$BERT > ${SAVE}/gen.txt

source scripts/calc_sacrebleu.sh $src $tgt $SAVE/gen.txt
```

