# `______` Documentation

Your docs should answer the following
 - [ ] Basic, what is it
 - [ ] what does it test
 - [ ] run it on the cluster/nichols
 - [ ] What might go wrong with this test, and how could we quickly fix it
 - [ ] Other

# What is `______`
What does it actually do

# What are the computational bottlenecks
Does the application take high memory, CPU, etc

# What steps did it take to install / run in your test
What did you have to do to run it as prep

# Issues and Troubleshooting
What might go wrong, what do people struggle with AND **how do we fix it quickly**

# Other

## MPI Run command Example:
```bash
mpirun \
  --hostfile ~/mpi_hosts \
  -np 18 \
  --map-by node \
  iqtree2-mpi \
    -s ~/alignment.fasta \
    -m MF \
    -T AUTO \
    --prefix ~/output/result \
    -B 1000 \
    --redo
```
- For this the hostfile `~/mpi_hosts` will be in format of `ip_address slots=7` with ip_address being a nodes ip and slots being equal to the number of cores
- np = number of nodes total
- The iqtree -s is the input file, in iqtree folder/example there are example files to use for this
