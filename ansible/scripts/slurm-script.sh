head_ip=172.171.1.1

echo orangepi | sudo -iS

# install munge
apt install munge libmunge2 libmunge-dev
#munge -n | unmunge | grep STATUS

# copy mungekey
scp orangepi@${head_ip}:/usr/sbin/munge.key /etc/munge/mungekey

# set permissions
chown -R munge: /etc/munge/ /var/log/munge/ /var/lib/munge/ /run/munge/
chmod 0700 /etc/munge/ /var/log/munge/ /var/lib/munge/
chmod 0755 /run/munge/
chmod 0700 /etc/munge/munge.key
chown -R munge: /etc/munge/munge.key

# Set munge up
systemctl enable --now munge
#systemctl status munge

# Build Slurm from source
apt-get install build-essential fakeroot devscripts equivs
tar -xaf slurm-24.05.2.tar.bz2
cd slurm-24.05.2
mk-build-deps -i -r debian/control
debuild -b -uc -us

# Create a slurm user
export SLURMUSER=1001
groupadd -g $SLURMUSER slurm
useradd  -m -c SLURM workload manager -d /var/lib/slurm -u $SLURMUSER -g slurm  -s /bin/bash slurm


# Install dependencies
dpkg -i slurm-smd_24.05.2-1_amd64.deb
dpkg -i slurm-smd-slurmd_24.05.2-1_amd64.deb
dpkg -i slurm-smd-client_24.05.2-1_amd64.deb

# fix potential broken dependencies
apt -y --fix-broken install

# leave root shell
exit
