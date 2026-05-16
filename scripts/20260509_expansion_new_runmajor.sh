#!/bin/bash
#SBATCH --job-name=expansion_new
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=72:00:00
#SBATCH --array=1-640
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=eeg37520@uga.edu
#SBATCH --output=/scratch/eeg37520/doliolid_slim_rebuild/logs/expansion_new_%A_%a.out
#SBATCH --error=/scratch/eeg37520/doliolid_slim_rebuild/logs/expansion_new_%A_%a.err

# 20260509_expansion_new_runmajor.sh
# Defense-scope new campaign Panel C (demographic expansion sweep).
# 2 cells (combos 26, 46) x 4 expansion factors x 80 runs = 640 tasks.
# Both cells K=25000, BANK_END_TICK=60000, T_EXPANSION=30000.
# Factors {10, 100, 1000, 5000} -> K_ANC {2500, 250, 25, 5} at K_post=25000.
#
# Three-axis decode on local task T (no chunking; 640 < MaxArraySize=5000):
#   COMBO_IDX  = ((T-1)        %% 2) + 1   -> COMBOS[COMBO_IDX-1] in {26, 46}
#   FACTOR_IDX = (((T-1) / 2)  %% 4) + 1   -> FACTORS[FACTOR_IDX-1]
#   RUN_ID     = ((T-1) / 8)   + 1
# Run-major: runs increment slowest. Under partial completion, uniform N
# across all 8 (combo x factor) cells.

set -e

REBUILD=/scratch/eeg37520/doliolid_slim_rebuild
PARAMFILE=$REBUILD/params/20260429_lifecycle_grid_100.tsv
CALFILE=$REBUILD/calibration/calibrated_mu_grid100.tsv
SLIMSCRIPT=$REBUILD/scripts/20260509_bank_expansion_15k.slim
BANKDIR=$REBUILD/banks_new

COMBOS=(26 46)
FACTORS=(10 100 1000 5000)
T_EXPANSION=30000
BANK_END_TICK=60000

T=$SLURM_ARRAY_TASK_ID

if [ "$T" -lt 1 ] || [ "$T" -gt 640 ]; then
    echo "ERROR: task T=$T out of range [1,640]"
    exit 1
fi

COMBO_IDX=$(( (T - 1) % 2 + 1 ))
FACTOR_IDX=$(( ((T - 1) / 2) % 4 + 1 ))
RUN_ID=$(( (T - 1) / 8 + 1 ))

COMBO_ID=${COMBOS[$((COMBO_IDX - 1))]}
EXPANSION_FACTOR=${FACTORS[$((FACTOR_IDX - 1))]}

cd $REBUILD
source /apps/eb/Miniforge3/24.11.3-0/etc/profile.d/conda.sh
conda activate slim_env

# Lifecycle params for this combo (param file has 15 header lines)
LINE=$(sed -n "$((15 + COMBO_ID))p" "$PARAMFILE")
K_NURSES=$(echo "$LINE" | awk '{print $2}')
OOZ_SURVIVAL=$(echo "$LINE" | awk '{print $3}')
NURSE_MORTALITY=$(echo "$LINE" | awk '{print $4}')
PHOROS=$(echo "$LINE" | awk '{print $5}')
GONOS=$(echo "$LINE" | awk '{print $6}')
EGGS=$(echo "$LINE" | awk '{print $7}')
SELFING=$(echo "$LINE" | awk '{print $8}')

# Calibrated MU for this combo
MU=$(awk -v c="$COMBO_ID" '$1==c {print $5; exit}' "$CALFILE")
if [ -z "$MU" ]; then
    echo "ERROR: no calibrated MU for combo $COMBO_ID in $CALFILE"
    exit 1
fi

# Ancestral K computed from post-expansion K and factor (integer division)
K_ANC=$(( K_NURSES / EXPANSION_FACTOR ))
if [ "$K_ANC" -lt 1 ]; then
    echo "ERROR: K_ANC=$K_ANC < 1 for combo $COMBO_ID factor $EXPANSION_FACTOR"
    exit 1
fi

# Defense-scope guard: this campaign is K=25k only
if [ "$K_NURSES" != "25000" ]; then
    echo "ERROR: expansion campaign limited to K=25000; got K=$K_NURSES for combo $COMBO_ID"
    exit 1
fi

mkdir -p $BANKDIR

echo "T=$T combo=$COMBO_ID factor_idx=$FACTOR_IDX expansion=$EXPANSION_FACTOR K_post=$K_NURSES K_anc=$K_ANC run=$RUN_ID MU=$MU"

slim \
    -d K_NURSES=$K_NURSES \
    -d K_ANC=$K_ANC \
    -d T_EXPANSION=$T_EXPANSION \
    -d FACTOR_IDX=$FACTOR_IDX \
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
