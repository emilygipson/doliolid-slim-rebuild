#!/bin/bash
#SBATCH --job-name=neut_cal_K10k_warm
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=72:00:00
#SBATCH --array=3,5,9
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=eeg37520@uga.edu
#SBATCH --output=/scratch/eeg37520/doliolid_slim_rebuild/logs/neut_cal_K10k_warm_%A_%a.out
#SBATCH --error=/scratch/eeg37520/doliolid_slim_rebuild/logs/neut_cal_K10k_warm_%A_%a.err

# Warm-start re-run of combos 3, 5, 9. Original iter 1 was killed at:
#   combo 3: tick 132500, window_mean ~0.0197 (equilibrated)
#   combo 5: tick 119500, window_mean ~0.0254 (still climbing)
#   combo 9: tick 181000, window_mean ~0.0222 (slowly declining)
#
# Warm-start MUs computed from MU_old * (TARGET_PI / observed_pi):
#   combo 3: 6.548e-07 * (0.006548 / 0.0197) = 2.176e-07
#   combo 5: 6.548e-07 * (0.006548 / 0.027)  = 1.588e-07  [biased low: pi was climbing]
#   combo 9: 6.548e-07 * (0.006548 / 0.020)  = 2.144e-07  [biased low: pi was declining toward this]
#
# Outer loop semantics unchanged from K=10k template; only starting MU differs.

set -e

REBUILD=/scratch/eeg37520/doliolid_slim_rebuild
PARAMFILE=$REBUILD/params/20260426_lifecycle_grid.tsv
TARGETFILE=$REBUILD/params/20260426_empirical_targets.tsv
SLIMSCRIPT=$REBUILD/scripts/20260426_neutral_calibration_15k.slim
LOGDIR=$REBUILD/calibration
OUTFILE=$LOGDIR/calibrated_mu.tsv

mkdir -p $LOGDIR

cd $REBUILD
source /apps/eb/Miniforge3/24.11.3-0/etc/profile.d/conda.sh
conda activate slim_env

HEADER_LINES=14
LINE_NUM=$((HEADER_LINES + SLURM_ARRAY_TASK_ID))
LINE=$(sed -n "${LINE_NUM}p" "$PARAMFILE")

COMBO_ID=$(echo "$LINE" | awk '{print $1}')
K_NURSES=$(echo "$LINE" | awk '{print $2}')
OOZ_SURVIVAL=$(echo "$LINE" | awk '{print $3}')
NURSE_MORTALITY=$(echo "$LINE" | awk '{print $4}')
PHOROS=$(echo "$LINE" | awk '{print $5}')
GONOS=$(echo "$LINE" | awk '{print $6}')
EGGS=$(echo "$LINE" | awk '{print $7}')
SELFING=$(echo "$LINE" | awk '{print $8}')

TARGET_PI=$(awk '$1=="pi" {print $2}' "$TARGETFILE")
GENOME_LENGTH=15135

# Warm-start MU per combo (overrides default TARGET_PI / K_NURSES formula)
case $COMBO_ID in
    3) MU=2.176e-07 ;;
    5) MU=1.588e-07 ;;
    9) MU=2.144e-07 ;;
    *) echo "ERROR: warm-start MU not defined for combo $COMBO_ID"; exit 1 ;;
esac

MAX_OUTER_ITER=5

echo "==================================================="
echo "Neutral calibration WARM-START: combo $COMBO_ID"
echo "  K_NURSES=$K_NURSES OOZ=$OOZ_SURVIVAL MORT=$NURSE_MORTALITY"
echo "  PHOROS=$PHOROS GONOS=$GONOS EGGS=$EGGS SELFING=$SELFING"
echo "  TARGET_PI=$TARGET_PI"
echo "  Starting MU (warm)=$MU"
echo "  MAX_OUTER_ITER=$MAX_OUTER_ITER"
echo "==================================================="

CONVERGED=0
FINAL_RATIO=""

for iter in $(seq 1 $MAX_OUTER_ITER); do
    echo ""
    echo "--- Outer iteration $iter, MU=$MU ---"

    ITER_LOG="$LOGDIR/combo${COMBO_ID}_warm_iter${iter}.log"

    slim \
        -d K_NURSES=$K_NURSES \
        -d MU=$MU \
        -d OOZ_SURVIVAL=$OOZ_SURVIVAL \
        -d NURSE_MORTALITY=$NURSE_MORTALITY \
        -d COMBO_ID=$COMBO_ID \
        -d TARGET_PI=$TARGET_PI \
        -d GENOME_LENGTH=$GENOME_LENGTH \
        -d PHOROS_PER_NURSE=$PHOROS \
        -d GONOS_PER_PHORO=$GONOS \
        -d EGGS_PER_GONO=$EGGS \
        -d SELFING_RATE=$SELFING \
        -d "LOGDIR='$LOGDIR'" \
        "$SLIMSCRIPT" 2>&1 | tee "$ITER_LOG"

    RATIO=$(grep -E "^\s*Ratio:" "$ITER_LOG" | tail -1 | awk '{print $2}')
    STATUS=$(grep -E "^\s*STATUS:" "$ITER_LOG" | tail -1 | awk '{print $2}')

    echo "--- Iteration $iter: STATUS=$STATUS RATIO=$RATIO ---"

    FINAL_RATIO=$RATIO

    if [ "$STATUS" == "CONVERGED" ]; then
        echo ""
        echo "==================================================="
        echo "Combo $COMBO_ID CONVERGED at MU=$MU after $iter iterations (warm-start)"
        echo "==================================================="
        echo -e "$COMBO_ID\t$K_NURSES\t$OOZ_SURVIVAL\t$NURSE_MORTALITY\t$MU\t$RATIO\t${iter}_warm\t$(date +%Y-%m-%d)" >> "$OUTFILE"
        CONVERGED=1
        break
    fi

    if [ -z "$RATIO" ]; then
        echo "ERROR: Could not parse ratio from iteration $iter log. Aborting."
        exit 1
    fi

    NEW_MU=$(python3 -c "print($MU / $RATIO)")
    echo "--- Adjusting MU: $MU -> $NEW_MU (divided by ratio $RATIO) ---"
    MU=$NEW_MU
done

if [ "$CONVERGED" == "0" ]; then
    echo ""
    echo "==================================================="
    echo "Combo $COMBO_ID FAILED to converge after $MAX_OUTER_ITER iterations (warm-start)"
    echo "Last MU=$MU, last ratio=$FINAL_RATIO"
    echo "==================================================="
    echo -e "$COMBO_ID\t$K_NURSES\t$OOZ_SURVIVAL\t$NURSE_MORTALITY\t$MU\t$FINAL_RATIO\tFAILED_${MAX_OUTER_ITER}_warm\t$(date +%Y-%m-%d)" >> "$OUTFILE"
    exit 1
fi
