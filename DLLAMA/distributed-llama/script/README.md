# SBCC DLLAMA Competition Scripts

## Quick Start

1. Edit `config.sh` with your actual Orange Pi IP addresses
2. Download models on root node: `python3 launch.py qwen3_8b_q40`
3. Ensure `dllama` is compiled on ALL nodes: `make dllama`
4. Run tasks

## Scripts

| Script | Purpose |
|--------|---------|
| `config.sh` | Shared configuration (IPs, paths, helpers) |
| `task1_llama31_baseline.sh` | Task 1: Fixed baseline (2 threads, 4 nodes, seq 4096) |
| `task2_qwen3_sweep.sh` | Task 2: Parameter sweep then `--final` for benchmarks |
| `task3_llama31_optimized.sh` | Task 3: `--sweep` for node count, then final benchmarks |

## Optimization Analysis

### Hardware: Orange Pi 5+ (RK3588)
- CPU: 4x Cortex-A76 @ 2.4GHz (big) + 4x Cortex-A55 @ 1.8GHz (little)
- RAM: 8-32GB LPDDR4x
- Network: Gigabit Ethernet

### Model Constraints
- Llama 3.1 8B: `nKvHeads=8` -> max 8 nodes (code enforces `nNodes <= nKvHeads`)
- Qwen 3 8B: `nKvHeads=8` -> max 8 nodes
- Q40 weights **require** `--buffer-float-type q80` (enforced in `app.cpp:239`)

---

### Optimization 1: Thread Count (Task 2 & 3)

**Problem:** RK3588 is big.LITTLE. Using `--nthreads 8` puts work on A55 cores which are ~40% slower. All threads must synchronize at barriers, so the slowest thread dictates throughput.

**Solution:** Use `--nthreads 4` to keep computation on big A76 cores only.

**Advanced:** Pin to big cores with `taskset -c 4-7 ./dllama worker ...` (on RK3588, CPUs 4-7 are typically the A76 big cores - verify with `lscpu`).

---

### Optimization 2: Lower max-seq-len (Task 2 & 3)

**Problem:** `--max-seq-len 4096` allocates KV cache for 4096 positions. The KV cache per layer is `2 * seq_len * kv_dim_per_node * sizeof(float)`. With 32 layers, this is significant memory that must stay in cache.

**Solution:** Lower `--max-seq-len` to the minimum that fits the benchmark prompts:
- If prompts are <500 tokens: use `--max-seq-len 1024`
- If prompts are <1500 tokens: use `--max-seq-len 2048`

This improves L2 cache hit rates on ARM.

---

### Optimization 3: More Nodes (Task 3)

**Problem:** With 4 nodes, each node processes 25% of the model per layer. With 8 nodes, each processes 12.5%.

**Trade-off:** More nodes = less compute per node BUT more network synchronization. With Gigabit Ethernet (~125 MB/s theoretical, ~110 MB/s practical), the sync data per layer is:
- Sync type Q80 with dim=4096: ~4KB per node per sync point
- 2 syncs per layer x 32 layers = 64 sync rounds
- With 8 nodes: each round sends/receives to 7 peers

**Recommendation:** Sweep 4, 6, and 8 nodes. For GigE, 4-8 nodes likely works well since the sync payload is small relative to compute time.

---

### Optimization 4: CPU Governor (Task 2 & 3)

Set all nodes to `performance` governor to prevent frequency scaling:
```bash
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```
This is safe (reverts on reboot) and prevents the CPU from downclocking between inference steps.

---

### Optimization 5: TCP Tuning (Task 3)

Increase socket buffer sizes on all nodes:
```bash
sudo sysctl -w net.core.rmem_max=16777216
sudo sysctl -w net.core.wmem_max=16777216
sudo sysctl -w net.ipv4.tcp_rmem="4096 1048576 16777216"
sudo sysctl -w net.ipv4.tcp_wmem="4096 1048576 16777216"
```
The code already sets `TCP_NODELAY` and `TCP_QUICKACK` (see `nn-network.cpp:52-66`), which is good. Larger buffers help with burst writes during sync.

---

### Optimization 6: Source Code Changes (Task 3 only)

#### 6a. Increase MAX_CHUNK_SIZE

In `src/nn/nn-network.cpp` line 24:
```cpp
// BEFORE:
#define MAX_CHUNK_SIZE 4096
// AFTER:
#define MAX_CHUNK_SIZE 65536
```

**Why:** Each `send()`/`recv()` call has syscall overhead. With 4KB chunks, a 256KB sync requires 64 syscalls. With 64KB chunks, it's only 4 syscalls. On ARM Linux, each syscall costs ~1-2us, which adds up across 64 sync rounds x 32 layers.

#### 6b. Add SO_SNDBUF/SO_RCVBUF to socket setup

In `src/nn/nn-network.cpp`, after `setNoDelay(sock)` in `connectSocket()` and after `setNoDelay(serverSocket)` in `createServerSocket()`, add:
```cpp
int bufSize = 1048576; // 1MB
setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &bufSize, sizeof(bufSize));
setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &bufSize, sizeof(bufSize));
```

#### 6c. Compiler flags (already good)

The Makefile already uses `-O3 -march=native -mtune=native -ffast-math -funroll-loops -flto=thin` which enables ARM NEON auto-vectorization. No changes needed.

---

### What NOT to Change

- `--buffer-float-type`: Must be `q80` for Q40 weights. Cannot use `f32` or `f16`.
- `--net-turbo`: Defaults to `1` (non-blocking sockets). Already optimal.
- `nBatches`: Defaults to `32`. This controls prompt evaluation batch size. Higher values have diminishing returns and 32 is well-tuned.

## Workflow

```
# 1. Task 1 baseline (all params fixed)
bash script/task1_llama31_baseline.sh

# 2. Task 2 sweep, find best params
bash script/task2_qwen3_sweep.sh
# Edit BEST_* values in script, then:
bash script/task2_qwen3_sweep.sh --final

# 3. Task 3 sweep node count
bash script/task3_llama31_optimized.sh --sweep
# Edit BEST_* values in script, then:
bash script/task3_llama31_optimized.sh
```
