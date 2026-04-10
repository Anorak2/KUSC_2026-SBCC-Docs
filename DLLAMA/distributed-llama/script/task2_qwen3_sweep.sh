#!/bin/bash
# Task 2: Qwen 3 8B Q40
#
# FIXED: 3 worker nodes (4 total), model/tokenizer/source unchanged
# TUNABLE: thread count, max-seq-len, other runtime params
#
# Strategy: The RK3588 has 4x Cortex-A76 (big) + 4x Cortex-A55 (little).
# We sweep thread counts to find the sweet spot. Key insight:
#   - 4 threads: stays on big cores only (if pinned), avoids slow A55 stalls
#   - 8 threads: uses all cores but little cores create stragglers
#   - Lower max-seq-len = smaller KV cache = better cache utilization
#
# Usage:
#   bash task2_qwen3_sweep.sh          # Run parameter sweep
#   bash task2_qwen3_sweep.sh --final  # Run final benchmarks (skip sweep)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/config.sh"

cd "$REPO_DIR"

RESULTS_DIR="${SCRIPT_DIR}/results/task2"
mkdir -p "$RESULTS_DIR"

# Tune all nodes first
tune_all_nodes "${WORKER_IPS_4[@]}"

# NOTE: nBatches (default 32) has NO CLI argument in dllama, so it can't be tuned.

# ============================================================
# FINAL BENCHMARKS (run with: bash task2_qwen3_sweep.sh --final)
# ============================================================
if [[ "${1:-}" == "--final" ]]; then
    # UPDATE THESE after sweep identifies the best configuration
    BEST_THREADS=4
    BEST_SEQ_LEN=2048

    echo "============================================"
    echo "  TASK 2: Final Benchmarks"
    echo "  threads=${BEST_THREADS} seq=${BEST_SEQ_LEN}"
    echo "============================================"

    WORKER_NTHREADS=$BEST_THREADS start_workers "${WORKER_IPS_4[@]}"

    for prompt_name in "short" "long" "leaderboard"; do
        case $prompt_name in
            short) prompt="$PROMPT_SHORT"; steps=64;;
            long) prompt="$PROMPT_LONG"; steps=256;;
            leaderboard) prompt="$PROMPT_LEADERBOARD"; steps=256;;
        esac

        outfile="${RESULTS_DIR}/final_${prompt_name}.txt"
        echo "--- Running final: ${prompt_name} ---"

        ./dllama inference \
            --model "$QWEN_MODEL" \
            --tokenizer "$QWEN_TOKENIZER" \
            --buffer-float-type q80 \
            --nthreads $BEST_THREADS \
            --max-seq-len $BEST_SEQ_LEN \
            --prompt "$prompt" \
            --steps $steps \
            --workers $WORKERS_4NODE \
            2>&1 | tee "$outfile"

        # Restart workers between runs
        stop_workers "${WORKER_IPS_4[@]}"
        WORKER_NTHREADS=$BEST_THREADS start_workers "${WORKER_IPS_4[@]}"
    done

    stop_workers "${WORKER_IPS_4[@]}"
    echo "Final results in: ${RESULTS_DIR}/final_*.txt"
    exit 0
fi

# ============================================================
# PARAMETER SWEEP (default mode)
# ============================================================
THREAD_COUNTS=(2 4 6 8)
SEQ_LENS=(1024 2048 4096)

echo "============================================"
echo "  TASK 2: Qwen 3 8B Q40 Parameter Sweep"
echo "  Testing threads: ${THREAD_COUNTS[*]}"
echo "  Testing seq lens: ${SEQ_LENS[*]}"
echo "============================================"

SWEEP_LOG="${RESULTS_DIR}/sweep_results.csv"
echo "threads,max_seq_len,prompt_name,eval_tok_s,pred_tok_s" > "$SWEEP_LOG"

for nthreads in "${THREAD_COUNTS[@]}"; do
    for seq_len in "${SEQ_LENS[@]}"; do
        echo ""
        echo "=== threads=${nthreads} seq_len=${seq_len} ==="

        # Start workers with this thread count
        WORKER_NTHREADS=$nthreads start_workers "${WORKER_IPS_4[@]}"

        outfile="${RESULTS_DIR}/t${nthreads}_s${seq_len}.txt"

        # Run a quick benchmark with the short prompt
        timeout 120 ./dllama inference \
            --model "$QWEN_MODEL" \
            --tokenizer "$QWEN_TOKENIZER" \
            --buffer-float-type q80 \
            --nthreads $nthreads \
            --max-seq-len $seq_len \
            --prompt "$PROMPT_SHORT" \
            --steps 48 \
            --workers $WORKERS_4NODE \
            2>&1 | tee "$outfile" || true

        # Extract tokens/s from output (first match = eval, second = pred)
        eval_toks=$(grep 'tokens/s' "$outfile" 2>/dev/null | head -1 | grep -oP '[0-9.]+' | head -1 || echo "N/A")
        pred_toks=$(grep 'tokens/s' "$outfile" 2>/dev/null | tail -1 | grep -oP '[0-9.]+' | head -1 || echo "N/A")
        echo "${nthreads},${seq_len},short,${eval_toks},${pred_toks}" >> "$SWEEP_LOG"

        stop_workers "${WORKER_IPS_4[@]}"
    done
done

echo ""
echo "============================================"
echo "  Sweep complete! Results: ${SWEEP_LOG}"
echo "============================================"
echo ""
echo "Top results by prediction tokens/s:"
sort -t, -k5 -rn "$SWEEP_LOG" | head -10
echo ""
echo "Update BEST_THREADS and BEST_SEQ_LEN in this script, then run:"
echo "  bash task2_qwen3_sweep.sh --final"
