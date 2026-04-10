#!/bin/bash
# Shared configuration for all task scripts
# Edit these values to match your cluster setup

# ============================================================
# NETWORK / NODE CONFIGURATION
# ============================================================
# Root node is the machine you run the script FROM.
# Workers are the remote Orange Pi's.
# Format: "IP:PORT" separated by spaces

# Task 1 & 2: exactly 3 workers (4 nodes total) as required
WORKERS_4NODE="172.17.1.101:9999 172.17.1.102:9999 172.17.1.103:9999"

# Task 3: up to 7 workers (8 nodes total, max for nKvHeads=8)
WORKERS_8NODE="172.17.1.101:9999 172.17.1.102:9999 172.17.1.103:9999 172.17.1.104:9999 172.17.1.105:9999 172.17.1.106:9999 172.17.1.107:9999"

# All worker IPs (for SSH commands - no port)
WORKER_IPS_4=(172.17.1.101 172.17.1.102 172.17.1.103)
WORKER_IPS_8=(172.17.1.101 172.17.1.102 172.17.1.103 172.17.1.104 172.17.1.105 172.17.1.106 172.17.1.107)

WORKER_PORT=9999
SSH_USER="orangepi"

# ============================================================
# PATHS (on each node - must be identical across all nodes)
# ============================================================
DLLAMA_DIR="/home/${SSH_USER}/distributed-llama"
DLLAMA_BIN="${DLLAMA_DIR}/dllama"

# Models (only needed on root node)
LLAMA_MODEL="models/llama3_1_8b_instruct_q40/dllama_model_llama3_1_8b_instruct_q40.m"
LLAMA_TOKENIZER="models/llama3_1_8b_instruct_q40/dllama_tokenizer_llama3_1_8b_instruct_q40.t"

QWEN_MODEL="models/qwen3_8b_q40/dllama_model_qwen3_8b_q40.m"
QWEN_TOKENIZER="models/qwen3_8b_q40/dllama_tokenizer_qwen3_8b_q40.t"

# ============================================================
# PROMPTS - update these when competition provides them
# ============================================================
PROMPT_SHORT="Hello, how are you today?"
PROMPT_LONG="Write a detailed essay about the history of artificial intelligence, from its origins in the 1950s to modern large language models. Cover key milestones, important researchers, and the major breakthroughs that shaped the field."
PROMPT_LEADERBOARD="placeholder - replace with competition prompt"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

start_workers() {
    local worker_ips=("$@")
    local nthreads=${WORKER_NTHREADS:-4}

    echo "Starting ${#worker_ips[@]} workers with ${nthreads} threads each..."
    for ip in "${worker_ips[@]}"; do
        echo "  Starting worker on ${ip}..."
        # Kill any existing worker, then start fresh
        ssh -o StrictHostKeyChecking=no ${SSH_USER}@${ip} \
            "pkill -f 'dllama worker' 2>/dev/null; sleep 0.5; cd ${DLLAMA_DIR} && nohup ${DLLAMA_BIN} worker --port ${WORKER_PORT} --nthreads ${nthreads} > /tmp/dllama_worker.log 2>&1 &" &
    done
    wait
    echo "Waiting for workers to be ready..."
    sleep 3
}

stop_workers() {
    local worker_ips=("$@")
    echo "Stopping workers..."
    for ip in "${worker_ips[@]}"; do
        ssh -o StrictHostKeyChecking=no ${SSH_USER}@${ip} "pkill -f 'dllama worker'" 2>/dev/null &
    done
    wait
    sleep 1
}

# Apply OS-level performance tuning on a node via SSH
# Safe and reversible - only changes CPU governor (resets on reboot)
tune_node() {
    local ip=$1
    ssh -o StrictHostKeyChecking=no ${SSH_USER}@${ip} bash -s <<'TUNE_EOF'
# Set CPU governor to performance (maximizes clock speed)
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | sudo tee "$gov" > /dev/null 2>&1
done
echo "CPU governor set to performance"
TUNE_EOF
}

tune_all_nodes() {
    local worker_ips=("$@")
    echo "Tuning root node..."
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance | sudo tee "$gov" > /dev/null 2>&1
    done
    echo "Tuning worker nodes..."
    for ip in "${worker_ips[@]}"; do
        tune_node "$ip" &
    done
    wait
}
