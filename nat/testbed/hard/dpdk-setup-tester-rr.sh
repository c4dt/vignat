
. ~/scripts/config.sh

. ~/scripts/dpdk-setup-functions.sh

sudo pkill -9 pktgen

set_numa_pages
load_igb_uio_module

#sudo ifconfig $TESTER_DEVICE_INTERNAL down
sudo ifconfig $TESTER_DEVICE_EXTERNAL down

#bind_nics_to_igb_uio $TESTER_PCI_INTERNAL
bind_nics_to_igb_uio $TESTER_PCI_EXTERNAL

sleep 8
bash ~/scripts/start-pktgen-rr-serv.sh