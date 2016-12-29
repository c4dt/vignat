#!/bin/bash
# Run the no-op DPDK plain forwarding application as the middlebox for the
# loopback scenario.
# The first argument ($1) provides the path to the config file.

CONFIG_PATH=$1

if [ -z $CONFIG_PATH ]; then
    CONFIG_PATH=.
fi

# WTF?
CONFIG_PATH=$HOME/vnds/nat/testbed/hard

. $CONFIG_PATH/config.sh

sudo pkill -9 $NAT_SRC_PATH/build/nat
sudo pkill -9 $OPT_NAT_SRC_PATH/build/nat
sudo pkill -9 $STUB_SRC_PATH/build/nat

cd $STUB_SRC_PATH

sudo rm build -rf
make

sudo $STUB_SRC_PATH/build/nat -c 0x01 -n 2 -- -p 0x3 --wan 0 --extip $MB_IP_EXTERNAL --eth-dest 0,$TESTER_MAC_EXTERNAL --eth-dest 1,$TESTER_MAC_INTERNAL

