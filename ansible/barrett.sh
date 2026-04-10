TZ="America/Los_Angeles" date >> timestamps.txt

mpirun --hostfile ~/mpi_hosts_good \
  -np 8 \
  --map-by node \
  --mca btl_tcp_if_include 172.17.1.0/24 \
  -wdir ~/hpl-2.3/bin/arm64 \
  -x OMP_NUM_THREADS=6 \
  -x OMP_PROC_BIND=TRUE \
  -x OMP_PLACES=cores \
  ./xhpl

TZ="America/Los_Angeles" date >> timestamps.txt
