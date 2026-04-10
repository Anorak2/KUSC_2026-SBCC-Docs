#!/bin/bash
# Task 3: Llama 3.1 8B Instruct Q40 - OPTIMIZED
#
# This task allows ALL optimizations: source code, runtime params, node count.
# Throughput is compared against your own Task 1 baseline.
#
# OPTIMIZATION STRATEGY:
# ============================================================
#
# 1. NODE COUNT (max 8 for Llama 3.1 8B, nKvHeads=8)
#    More nodes = less compute per node, but more network overhead.
#    Sweet spot depends on network latency. We sweep 4, 6, 8 nodes.
#
# 2. CPU GOVERNOR = performance
#    Prevents frequency scaling during inference.
#
# 3. THREAD COUNT = 4 per node (big cores only on RK3588)
#    RK3588: 4x A76 @ 2.4GHz + 4x A55 @ 1.8GHz
#    LITTLE cores are ~40% slower and create straggler threads.
#    4 threads keeps work on big cores.
#
# 4. LOWER max-seq-len (if prompts allow)
#    Smaller KV cache = better L2 cache utilization on ARM.
#    4096 -> 2048 or 1024 depending on prompt length.
#
# 5. SOURCE CODE CHANGES (apply before running):
#    See script/README.md for full details.
#    a) Increase MAX_CHUNK_SIZE in nn-network.cpp: 4096 -> 65536
#       Reduces syscall overhead for network transfers.
#    b) Increase socket buffer sizes (SO_SNDBUF/SO_RCVBUF)
#    c) OS-level TCP tuning
#
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/config.sh"

cd "$REPO_DIR"

RESULTS_DIR="${SCRIPT_DIR}/results/task3"
mkdir -p "$RESULTS_DIR"

# ============================================================
# OS-LEVEL TUNING (safe, reverts on reboot)
# ============================================================
apply_os_tuning() {
    local ip=$1
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${ip} bash -s <<'EOF'
# CPU governor -> performance
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | sudo tee "$gov" > /dev/null 2>&1
done

# TCP tuning: larger socket buffers for faster sync
sudo sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
sudo sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_rmem="4096 1048576 16777216" 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_wmem="4096 1048576 16777216" 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_no_metrics_save=1 2>/dev/null || true

echo "OS tuning applied"
EOF
}

echo "Applying OS tuning to all nodes..."
# Tune root
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | sudo tee "$gov" > /dev/null 2>&1
done
sudo sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
sudo sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_rmem="4096 1048576 16777216" 2>/dev/null || true
sudo sysctl -w net.ipv4.tcp_wmem="4096 1048576 16777216" 2>/dev/null || true

# Tune workers (ignore failures for nodes that don't exist yet)
for ip in "${WORKER_IPS_8[@]}"; do
    apply_os_tuning "$ip" &
done
wait || true

# ============================================================
# SWEEP: Find optimal node count
# ============================================================
if [[ "${1:-}" == "--sweep" ]]; then
    echo "============================================"
    echo "  TASK 3: Node Count Sweep"
    echo "============================================"

    NTHREADS=4
    SEQ_LEN=2048
    SWEEP_LOG="${RESULTS_DIR}/node_sweep.csv"
    echo "nodes,threads,seq_len,eval_tok_s,pred_tok_s" > "$SWEEP_LOG"

    # Test with 4 nodes (3 workers) - same as baseline but optimized params
    for node_count in 4 6 8; do
        case $node_count in
            4) workers="$WORKERS_4NODE"; worker_ips=("${WORKER_IPS_4[@]}");;
            6) workers="${WORKER_IPS_8[0]}:9999 ${WORKER_IPS_8[1]}:9999 ${WORKER_IPS_8[2]}:9999 ${WORKER_IPS_8[3]}:9999 ${WORKER_IPS_8[4]}:9999"
               worker_ips=("${WORKER_IPS_8[@]:0:5}");;
            8) workers="$WORKERS_8NODE"; worker_ips=("${WORKER_IPS_8[@]}");;
        esac

        echo ""
        echo "=== Testing ${node_count} nodes, ${NTHREADS} threads ==="

        WORKER_NTHREADS=$NTHREADS start_workers "${worker_ips[@]}"

        outfile="${RESULTS_DIR}/sweep_${node_count}nodes.txt"
        timeout 120 ./dllama inference \
            --model "$LLAMA_MODEL" \
            --tokenizer "$LLAMA_TOKENIZER" \
            --buffer-float-type q80 \
            --nthreads $NTHREADS \
            --max-seq-len $SEQ_LEN \
            --prompt "$PROMPT_SHORT" \
            --steps 48 \
            --workers $workers \
            2>&1 | tee "$outfile" || true

        eval_toks=$(grep 'tokens/s' "$outfile" 2>/dev/null | head -1 | grep -oP '[0-9.]+' | head -1 || echo "N/A")
        pred_toks=$(grep 'tokens/s' "$outfile" 2>/dev/null | tail -1 | grep -oP '[0-9.]+' | head -1 || echo "N/A")
        echo "${node_count},${NTHREADS},${SEQ_LEN},${eval_toks},${pred_toks}" >> "$SWEEP_LOG"

        stop_workers "${worker_ips[@]}"
    done

    echo ""
    echo "Node sweep results:"
    cat "$SWEEP_LOG"
    echo ""
    echo "Pick the best node count and update BEST_NODES below for --final"
    exit 0
fi

# ============================================================
# FINAL OPTIMIZED BENCHMARKS
# ============================================================
# UPDATE THESE after sweep
BEST_NODES=8          # Likely 4 or 8 depending on network
BEST_THREADS=4        # Big cores only
BEST_SEQ_LEN=2048     # Lower if prompts fit; raises perf via cache
BEST_BATCHES=32       # Default is good

# Build worker list for the chosen node count (BEST_NODES includes root)
NUM_WORKERS=$((BEST_NODES - 1))
if (( NUM_WORKERS < 1 || NUM_WORKERS > 7 )); then
    echo "BEST_NODES must be between 2 and 8 (got ${BEST_NODES})"; exit 1
fi
W_IPS=("${WORKER_IPS_8[@]:0:$NUM_WORKERS}")
WORKERS=""
for ip in "${W_IPS[@]}"; do
    WORKERS="${WORKERS} ${ip}:${WORKER_PORT}"
done
WORKERS="${WORKERS# }"  # trim leading space

echo "============================================"
echo "  TASK 3: Llama 3.1 8B Optimized"
echo "  Nodes: ${BEST_NODES}"
echo "  Threads/node: ${BEST_THREADS}"
echo "  Max seq len: ${BEST_SEQ_LEN}"
echo "  Batches: ${BEST_BATCHES}"
echo "============================================"

WORKER_NTHREADS=$BEST_THREADS start_workers "${W_IPS[@]}"

for prompt_name in "short" "long" "leaderboard"; do
    case $prompt_name in
        short) prompt="$PROMPT_SHORT"; steps=64;;
        long) prompt="$PROMPT_LONG"; steps=256;;
        leaderboard) prompt="$PROMPT_LEADERBOARD"; steps=256;;
    esac

    outfile="${RESULTS_DIR}/final_${prompt_name}.txt"
    echo ""
    echo "--- Running: ${prompt_name} (steps=${steps}) ---"

    ./dllama inference \
        --model "$LLAMA_MODEL" \
        --tokenizer "$LLAMA_TOKENIZER" \
        --buffer-float-type q80 \
        --nthreads $BEST_THREADS \
        --max-seq-len $BEST_SEQ_LEN \
        --prompt "$prompt" \
        --steps $steps \
        --workers $WORKERS \
        2>&1 | tee "$outfile"

    echo "Results saved to: $outfile"

    stop_workers "${W_IPS[@]}"
    WORKER_NTHREADS=$BEST_THREADS start_workers "${W_IPS[@]}"
done

stop_workers "${W_IPS[@]}"

echo ""
echo "============================================"
echo "  Task 3 complete. Results in: ${RESULTS_DIR}"
echo "  Compare against Task 1 for speedup ratio."
echo "============================================"
