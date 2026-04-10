# Distributed Llama (DLLAMA) Documentation

## What is Distributed Llama

Distributed Llama splits LLM inference across multiple devices using tensor parallelism over Ethernet. One node acts as the root (loads the model and coordinates), and the rest act as workers. Each node holds a slice of the model in RAM, so the memory cost is split across all nodes.

The binary we build is `dllama`. It supports `inference` (benchmark), `chat`, and `worker` subcommands. There's also `dllama-api` for an HTTP-compatible API server.

Upstream repo: https://github.com/b4rtaz/distributed-llama

## What does it test

CPU-bound matrix multiplications (quantized int4/int8 GEMM), memory bandwidth (loading weights), and network throughput between nodes (synchronizing activations over TCP). The bottleneck on the Orange Pi's will be CPU compute and network latency between nodes.

## What are the computational bottlenecks

- **CPU**: The bulk of time is spent in quantized matrix multiplications on ARM NEON. More cores and higher clock speeds help directly.
- **RAM bandwidth**: Weights are streamed from memory every token. The Orange Pi's LPDDR4 bandwidth is the ceiling here.
- **Network**: Every layer requires a round-trip sync between all nodes. Gigabit Ethernet is fine for small models, but larger models will bottleneck on network latency and bandwidth. Use a direct switch, not WiFi.

Node count must divide evenly into the model dimensions. Valid counts for Llama 3.1 8B (which has 8 KV heads): 1, 2, 4, or 8 nodes. The code enforces `nNodes <= nKvHeads`, so 8 is the hard max. The team should sweep 4 vs 8 nodes during competition to find the throughput sweet spot (more nodes = less compute per node but more network sync overhead).

## What steps did it take to install / run

### On every node (root + workers):

```bash
sudo apt install git build-essential
git clone https://github.com/b4rtaz/distributed-llama.git
cd distributed-llama
make clean && make -j8 dllama
```

> **Warning:** The Makefile uses `-march=native`, which generates CPU-specific instructions. Each node **must** compile its own binary. Do not copy a binary compiled on one board to another — it can segfault due to differing hardware revisions.

> **Note:** `python3` is required for `launch.py`. Armbian CLI images may not include it — install with `sudo apt install python3` if missing.

### On the root node only, download a model:

> **Note:** Model download requires internet access on the root node. Pre-download models before competition day to avoid delays.

```bash
python3 launch.py llama3_1_8b_instruct_q40
```

### Start workers (on each worker node):

```bash
./dllama worker --port 9999 --nthreads 4
```

### Run inference benchmark (on root):

```bash
./dllama inference \
  --prompt "Hello world" \
  --steps 32 \
  --model models/llama3_1_8b_instruct_q40/dllama_model_llama3_1_8b_instruct_q40.m \
  --tokenizer models/llama3_1_8b_instruct_q40/dllama_tokenizer_llama3_1_8b_instruct_q40.t \
  --buffer-float-type q80 \
  --nthreads 4 \
  --max-seq-len 4096 \
  --workers 172.17.1.51:9999 172.17.1.52:9999 172.17.1.53:9999
```

We use `--nthreads 4` (not 8) because the RK3588 is a big.LITTLE CPU: 4x Cortex-A76 (fast) + 4x Cortex-A55 (slow). Using 8 threads puts work on the slow A55 cores, which create straggler threads that bottleneck inference since all threads must synchronize at barriers. Keeping to 4 threads ensures computation stays on the fast A76 big cores only.

## Changes from upstream

We forked from upstream and made two fixes to the `Makefile` for GCC on the Orange Pi's. No inference code was changed.

### 1. `-flto=thin` changed to `-flto=auto`

**Line 5 of `Makefile`**

The upstream Makefile uses `-flto=thin`, which is a Clang/LLVM-only flag. The Orange Pi's use GCC (from `build-essential`), so GCC silently ignores this and LTO never gets applied.

`-flto=auto` is the GCC-compatible equivalent. It tells GCC to use all available cores during link-time optimization. This should produce a faster binary since the compiler can now optimize across translation units.

```makefile
# upstream
CXXFLAGS += -march=native -mtune=native -O3 -ffast-math -funroll-loops -flto=thin

# ours
CXXFLAGS += -march=native -mtune=native -O3 -ffast-math -funroll-loops -flto=auto
```

### 2. Removed duplicate `-O3`

**Lines 8-12 of `Makefile`**

The upstream Makefile adds `-O3` on line 5 (inside the `ifndef TERMUX_VERSION` block, which is always true on the Pi's), then adds it again in the `else` branch of the `DEBUG` ifdef on line 11. The second `-O3` does nothing since it's already set.

We removed the `else` branch to avoid confusion. Behavior is identical.

```makefile
# upstream
ifdef DEBUG
    CXXFLAGS += -g -fsanitize=address
else
    CXXFLAGS += -O3
endif

# ours
ifdef DEBUG
    CXXFLAGS += -g -fsanitize=address
endif
```

### What we intentionally left alone

- The Makefile doesn't track header (`.hpp`) dependencies on `.o` targets. This means if you edit a header, you need to `make clean && make -j8 dllama` instead of just `make`. Fixing this would require a bigger Makefile restructure and isn't worth it for competition prep.
- `.PHONY: dllama` is declared intentionally because of the missing header deps.
- The rest of the build flags (`-march=native`, `-mtune=native`, `-ffast-math`, `-funroll-loops`) are already good for ARM.

## Issues and Troubleshooting

**Build fails after editing a header file**: The Makefile doesn't track `.hpp` dependencies. We have to run `make clean && make -j8 dllama` instead of just `make`.

**Slow inference**: Use `--nthreads 4` (big cores only), not 8. The RK3588's slow A55 cores create straggler threads that bottleneck all of inference. See the thread count explanation above.

**Node count errors**: Node count (root + workers) must be a power of 2. If we have 4 total nodes that's valid, while 2 workers with 3 nodes is invalid

## Other

- The `launch.py` script handles downloading models from HuggingFace. 
- `dllama-api` exposes an OpenAI-compatible HTTP API if you want to test with a web UI. See the upstream docs for details.
- Only `q40` model with `q80` buffer-float-type and `f32` model with `f32` buffer-float-type quantization combos are supported.
- For automated deployment to all nodes, use the Ansible playbook: `ansible/install_dllama.yml`.
