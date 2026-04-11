import os
import re
import matplotlib.pyplot as plt

DATA_DIR = "/home/orangepi/iqtree_workdir/outputFolder/hiv100"

cpu_time_pattern = re.compile(r"Total CPU time used:\s+([\d\.]+)")
thread_from_fname = re.compile(r"_t(\d+)")

data = []

for fname in os.listdir(DATA_DIR):
    if fname.endswith(".iqtree"):
        path = os.path.join(DATA_DIR, fname)

        with open(path, "r") as f:
            text = f.read()

        cpu_match = cpu_time_pattern.search(text)
        thread_match = thread_from_fname.search(fname)

        if cpu_match and thread_match:
            cpu_time = float(cpu_match.group(1))
            threads = int(thread_match.group(1))
            data.append((threads, cpu_time))

# 🛑 Safety check
if not data:
    raise ValueError("No data parsed — check patterns.")

# Sort
data.sort()
threads = [d[0] for d in data]
cpu_times = [d[1] for d in data]

# Baseline = 1 thread
baseline_time = cpu_times[threads.index(1)]

# Compute metrics
speedup = [baseline_time / t for t in cpu_times]
efficiency = [s / n for s, n in zip(speedup, threads)]

# ---- Plot 1 ----
plt.figure()
plt.plot(threads, cpu_times, marker='o')
plt.xlabel("Thread Count")
plt.ylabel("Total CPU Time (s)")
plt.title("CPU Time vs Thread Count")
plt.grid(True)
plt.savefig("cpu_scaling.png")

# ---- Plot 2 ----
plt.figure()
plt.plot(threads, speedup, marker='o')
plt.xlabel("Thread Count")
plt.ylabel("Speedup")
plt.title("Speedup vs Thread Count")
plt.grid(True)
plt.savefig("speedup.png")

# ---- Plot 3 ----
plt.figure()
plt.plot(threads, efficiency, marker='o')
plt.xlabel("Thread Count")
plt.ylabel("Parallel Efficiency")
plt.title("Efficiency vs Thread Count")
plt.grid(True)
plt.savefig("efficiency.png")

plt.close("all")
