#!/bin/bash
#SBATCH --job-name=bank_dispatch
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=168:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=eeg37520@uga.edu
#SBATCH --output=/scratch/eeg37520/doliolid_slim_rebuild/logs/bank_dispatcher_%j.out
#SBATCH --error=/scratch/eeg37520/doliolid_slim_rebuild/logs/bank_dispatcher_%j.err

DIR=/scratch/eeg37520/doliolid_slim_rebuild
CAL=$DIR/calibration/calibrated_mu_grid100.tsv
BANKS=$DIR/banks
WRAPPER=$DIR/scripts/20260429_run_bank_combo.sh
LOG=$BANKS/dispatched.log
HIST=$BANKS/dispatch_history.log

mkdir -p $BANKS
touch $LOG $HIST

while true; do
    combos=$(awk '$1 ~ /^[0-9]+$/ && $7 !~ /FAILED/ && ($2==10000 || $2==25000 || $2==50000) {print $1}' $CAL | sort -u)
    n=0

    for c in $combos; do
        grep -qx "$c" $LOG && continue

        bf=$BANKS/bank_combo${c}.tsv
        if [ -s "$bf" ]; then
            echo $c >> $LOG
            echo "$(date) $c skipped (bank exists)" >> $HIST
            continue
        fi

        jid=$(sbatch --parsable --export=ALL,COMBO_ID=$c $WRAPPER)
        if [ -n "$jid" ]; then
            echo $c >> $LOG
            echo "$(date) $c -> $jid" >> $HIST
            n=$((n+1))
        fi

        [ $n -ge 5 ] && break
    done

    [ $(wc -l < $LOG) -ge 75 ] && exit 0
    sleep 600
done
