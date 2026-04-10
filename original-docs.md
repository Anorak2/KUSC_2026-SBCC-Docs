## Orange PI's
**Turning Them ON**
Use the good usb serial converter, don't daisy chain wires or it fucking breaks. If you're trying to screen in then unplug the ethernet first, and probably hdmi for good measure.

**Providing Power to the Orange Pi's**
viewing the pin stack so that it's close to you, on farthest right side there is one empty pin, then purple, then white. Purple if 5v and white is ground

```[   ...     ][   white(GRND)     ][     purple(5V)     ][       empty       ]```

 **Pi5**
http://www.orangepi.org/orangepiwiki/index.php/Orange_Pi_5
- `sudo screen /dev/tty0 1500000`

 **Getting into Pi5**
- `screen /dev/ttyUSB0 1500000`
- `ssh orangepi@ip.addr`

## Network Planning
Ethernet connections:
if you view the ethernet ports from the front (where you plug it in) then WAN is on the right and LAN is on the left

| name      | value                   |
| --------- | ----------------------- |
| subnet    | 172.17.1.0/24           |
| da router | 172.171.1.1             |
| dns       | 8.8.8.8 8.8.4.4         |
| dhcp pool | 172.171.100 172.171.200 |
| wan       | enP3p49s0               |
| lan       | enP4p65s0               |

Find the orangepi with `nmap -sN -p 22 172.16.50.*' 
ARP scan
`sudo arp-scan --interface= -l`

The DHCP server 
`isc-dhcp-server.service`

wan address is at 172.20.200.2

## Ansible
The ansible configuration files are on the head orangepi 5+, the top one on the stack. The password to the locked vault is `orangepi`

```ansible-playbook --ask-vault-pass -i inventory.ini package.yml```

