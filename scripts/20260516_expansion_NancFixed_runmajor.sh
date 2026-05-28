#!/bin/bash
#SBATCH --job-name=expansion_nfx
#SBATCH --partition=batch
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=96:00:00
#SBATCH --array=1-800
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=eeg37520@uga.edu
#SBATCH --output=/scratch/eeg37520/doliolid_slim_rebuild/logs/expansion_nfx_%A_%a.out
#SBATCH --error=/scratch/eeg37520/doliolid_slim_rebuild/logs/expansion_nfx_%A_%a.err

# 20260516_expansion_NancFixed_runmajor.sh
# Panel C redesign: N_anc fixed, N_final varies.
# 2 cells (combos 26, 46) x 5 factors x 80 runs = 800 tasks.
# N_anc = 500, factors {10, 20, 40, 70, 100} -> N_final {5000, 10000, 20000, 35000, 50000}.
# T_EXPANSION=30000, BANK_END_TICK=60000.
# Mu values from K=25000 steady-state calibration; not retuned per cell.
#
# Three-axis decode on local task T:
#   COMBO_IDX  = ((T-1)        %% 2) + 1   -> COMBOS[COMBO_IDX-1] in {26, 46}
#   FACTOR_IDX = (((T-1) / 2)  %% 5) + 1   -> FACTORS[FACTOR_IDX-1]
#   RUN_ID     = ((T-1) / 10)  + 1
# Run-major: runs increment slowest. Partial completion gives uniform N
# across all 10 (combo x factor) cells.

set -e

REBUILD=/scratch/eeg37520/doliolid_slim_rebuild
PARAMFILE=$REBUILD/params/20260429_lifecycle_grid_100.tsv
CALFILE=$REBUILD/calibration/calibrated_mu_grid100.tsv
SLIMSCRIPT=$REBUILD/scripts/20260516_bank_expansion_NancFixed_15k.slim
BANKDIR=$REBUILD/banks_new

COMBOS=(26 46)
FACTORS=(10 20 40 70 100)
N_ANC=500
T_EXPANSION=30000
BANK_END_TICK=60000

T=$SLURM_ARRAY_TASK_ID

if [ "$T" -lt 1 ] || [ "$T" -gt 800 ]; then
    echo "ERROR: task T=$T out of range [1,800]"
    exit 1
fi

COMBO_IDX=$(( (T - 1) % 2 + 1 ))
FACTOR_IDX=$(( ((T - 1) / 2) % 5 + 1 ))
RUN_ID=$(( (T - 1) / 10 + 1 ))

COMBO_ID=${COMBOS[$((COMBO_IDX - 1))]}
EXPANSION_FACTOR=${FACTORS[$((FACTOR_IDX - 1))]}

cd $REBUILD
source /apps/eb/Miniforge3/24.11.3-0/etc/profile.d/conda.sh
conda activate slim_env

# Lifecycle params for this combo (param file has 15 header lines).
# Note: K column of the lifecycle TSV is IGNORED in this design.
LINE=$(sed -n "$((15 + COMBO_ID))p" "$PARAMFILE")
OOZ_SURVIVAL=$(echo "$LINE" | awk '{print $3}')
NURSE_MORTALITY=$(echo "$LINE" | awk '{print $4}')
PHOROS=$(echo "$LINE" | awk '{print $5}')
GONOS=$(echo "$LINE" | awk '{print $6}')
EGGS=$(echo "$LINE" | awk '{print $7}')
SELFING=$(echo "$LINE" | awk '{print $8}')

# Calibrated MU for this combo (from K=25k calibration; reused without retune)
MU=$(awk -v c="$COMBO_ID" '$1==c {print $5; exit}' "$CALFILE")
if [ -z "$MU" ]; then
    echo "ERROR: no calibrated MU for combo $COMBO_ID in $CALFILE"
    exit 1
fi

# Compute N_final from fixed N_anc and the factor
N_FINAL=$(( N_ANC * EXPANSION_FACTOR ))
if [ "$N_FINAL" -lt "$N_ANC" ]; then
    echo "ERROR: N_FINAL=$N_FINAL < N_ANC=$N_ANC; check factor=$EXPANSION_FACTOR"
    exit 1
fi

mkdir -p $BANKDIR

echo "T=$T combo=$COMBO_ID factor_idx=$FACTOR_IDX expansion=$EXPANSION_FACTOR N_anc=$N_ANC N_final=$N_FINAL run=$RUN_ID MU=$MU"

slim \
    -d N_ANC=$N_ANC \
    -d N_FINAL=$N_FINAL \
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
