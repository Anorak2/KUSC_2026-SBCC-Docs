#!/bin/bash
# Task 1: Llama 3.1 8B Instruct Q40 - BASELINE
#
# FIXED PARAMETERS (per competition rules):
#   - 3 worker nodes (4 total)
#   - 2 threads per node
#   - max-seq-len 4096
#   - No source code changes
#   - buffer-float-type q80 (required by dllama for Q40 weights)
#
# This task serves as the baseline for Task 3 comparison.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/config.sh"

cd "$REPO_DIR"

NTHREADS=2
MAX_SEQ_LEN=4096
RESULTS_DIR="${SCRIPT_DIR}/results/task1"
mkdir -p "$RESULTS_DIR"

echo "============================================"
echo "  TASK 1: Llama 3.1 8B Q40 Baseline"
echo "  Nodes: 4 (1 root + 3 workers)"
echo "  Threads/node: ${NTHREADS}"
echo "  Max seq len: ${MAX_SEQ_LEN}"
echo "============================================"

# Start workers with 2 threads
WORKER_NTHREADS=$NTHREADS start_workers "${WORKER_IPS_4[@]}"

run_benchmark() {
    local prompt_name=$1
    local prompt_text=$2
    local steps=$3
    local outfile="${RESULTS_DIR}/${prompt_name}.txt"

    echo ""
    echo "--- Running: ${prompt_name} (steps=${steps}) ---"

    ./dllama inference \
        --model "$LLAMA_MODEL" \
        --tokenizer "$LLAMA_TOKENIZER" \
        --buffer-float-type q80 \
        --nthreads $NTHREADS \
        --max-seq-len $MAX_SEQ_LEN \
        --prompt "$prompt_text" \
        --steps $steps \
        --workers $WORKERS_4NODE \
        2>&1 | tee "$outfile"

    echo ""
    echo "Results saved to: $outfile"
}

# Run short prompt
run_benchmark "short" "$PROMPT_SHORT" 64

# Restart workers between runs to reset state
stop_workers "${WORKER_IPS_4[@]}"
WORKER_NTHREADS=$NTHREADS start_workers "${WORKER_IPS_4[@]}"

# Run long prompt
run_benchmark "long" "$PROMPT_LONG" 256

stop_workers "${WORKER_IPS_4[@]}"
WORKER_NTHREADS=$NTHREADS start_workers "${WORKER_IPS_4[@]}"

# Run leaderboard prompt
run_benchmark "leaderboard" "$PROMPT_LEADERBOARD" 256

stop_workers "${WORKER_IPS_4[@]}"

echo ""
echo "============================================"
echo "  Task 1 complete. Results in: ${RESULTS_DIR}"
echo "============================================"
