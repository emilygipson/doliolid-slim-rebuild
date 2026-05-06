#!/bin/bash
#SBATCH --job-name=megabank
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=72:00:00
#SBATCH --array=1-4875
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=eeg37520@uga.edu
#SBATCH --output=/scratch/eeg37520/doliolid_slim_rebuild/logs/megabank_%A_%a.out
#SBATCH --error=/scratch/eeg37520/doliolid_slim_rebuild/logs/megabank_%A_%a.err

# 20260506_megabank_neutral_runmajor.sh
# Defense-scope neutral mega-array: 75 combos x 130 runs = 9750 global tasks.
# Sapelo MaxArraySize=5000 forces a split into two chunks of 4875.
# Submit each chunk by passing CHUNK_OFFSET via --export:
#   sbatch --export=ALL,CHUNK_OFFSET=0    <this script>
#   sbatch --export=ALL,CHUNK_OFFSET=4875 <this script>
#
# Run-major indexing on global task T:
#   T = SLURM_ARRAY_TASK_ID + CHUNK_OFFSET
#   COMBO_ID = ((T-1) %% 75) + 1
#   RUN_ID   = ((T-1) /  75) + 1
#
# Run-major chosen so partial completion gives uniform N across all 75 combos
# rather than full data on some cells and none on others.
#
# Mail-type is FAIL only because END on 9750 tasks would generate 9750 emails.

set -e

REBUILD=/scratch/eeg37520/doliolid_slim_rebuild
PARAMFILE=$REBUILD/params/20260429_lifecycle_grid_100.tsv
CALFILE=$REBUILD/calibration/calibrated_mu_grid100.tsv
SLIMSCRIPT=$REBUILD/scripts/20260429_bank_independent_15k.slim
BANKDIR=$REBUILD/banks

# Default offset to 0 if not exported
: "${CHUNK_OFFSET:=0}"

# Decode global task ID into (combo, run) under run-major
T=$(( SLURM_ARRAY_TASK_ID + CHUNK_OFFSET ))

if [ "$T" -lt 1 ] || [ "$T" -gt 9750 ]; then
    echo "ERROR: global T=$T out of range [1,9750] (local task=$SLURM_ARRAY_TASK_ID, offset=$CHUNK_OFFSET)"
    exit 1
fi

COMBO_ID=$(( (T - 1) % 75 + 1 ))
RUN_ID=$(( (T - 1) / 75 + 1 ))

if [ "$COMBO_ID" -lt 1 ] || [ "$COMBO_ID" -gt 75 ]; then
    echo "ERROR: invalid COMBO_ID=$COMBO_ID from global task $T"
    exit 1
fi

cd $REBUILD
source /apps/eb/Miniforge3/24.11.3-0/etc/profile.d/conda.sh
conda activate slim_env

# Look up combo parameters (param file has 15 header lines)
LINE=$(sed -n "$((15 + COMBO_ID))p" "$PARAMFILE")
K_NURSES=$(echo "$LINE" | awk '{print $2}')
OOZ_SURVIVAL=$(echo "$LINE" | awk '{print $3}')
NURSE_MORTALITY=$(echo "$LINE" | awk '{print $4}')
PHOROS=$(echo "$LINE" | awk '{print $5}')
GONOS=$(echo "$LINE" | awk '{print $6}')
EGGS=$(echo "$LINE" | awk '{print $7}')
SELFING=$(echo "$LINE" | awk '{print $8}')

# Look up calibrated MU for this combo
MU=$(awk -v c="$COMBO_ID" '$1==c {print $5; exit}' "$CALFILE")
if [ -z "$MU" ]; then
    echo "ERROR: no calibrated MU for combo $COMBO_ID in $CALFILE"
    exit 1
fi

# Bank end tick scaled to K (matches original per-combo wrapper)
case $K_NURSES in
    10000) BANK_END_TICK=30000  ;;
    25000) BANK_END_TICK=60000  ;;
    50000) BANK_END_TICK=120000 ;;
    *) echo "ERROR: K=$K_NURSES outside defense scope (10k/25k/50k only)"; exit 1 ;;
esac

echo "globalT=$T combo=$COMBO_ID run=$RUN_ID K=$K_NURSES MU=$MU end=$BANK_END_TICK chunk_offset=$CHUNK_OFFSET"

mkdir -p $BANKDIR

slim \
    -d K_NURSES=$K_NURSES \
    -d MU=$MU \
    -d OOZ_SURVIVAL=$OOZ_SURVIVAL \
    -d NURSE_MORTALITY=$NURSE_MORTALITY \
    -d COMBO_ID=$COMBO_ID \
    -d BANK_RUN_ID=$RUN_ID \
    -d GENOME_LENGTH=15135 \
    -d PHOROS_PER_NURSE=$PHOROS \
    -d GONOS_PER_PHORO=$GONOS \
    -d EGGS_PER_GONO=$EGGS \
    -d SELFING_RATE=$SELFING \
    -d BANK_END_TICK=$BANK_END_TICK \
    -d "BANKDIR='$BANKDIR'" \
    "$SLIMSCRIPT"
