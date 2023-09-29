#!/bin/bash

SERVER_USERNAME="user"
SERVER_USER_PASS="pass"
TOFINO_USERNAME="tofino"
TOFINO_USER_PASS="tofino"
SWITCHAROO_TOFINO_NAME="tofino32p"
MCAST_TOFINO_NAME="tofino64p"
GENERATOR_SERVER_NAME="nslrack25"

SWITCHAROO_PATH="/absolute/path/to/switcharoo"
MULTICAST_PATH="/absolute/path/to/switcharoo_mcast"
GENERATOR_PATH="/absolute/path/to/generator"

MULTICAST_TOFINO_SDE="/home/tofino/bf-sde-9.7.0"
MULTICAST_TOFINO_SDE_INSTALL="$MULTICAST_TOFINO_SDE/install"

SWITCHAROO_TOFINO_SDE="/home/tofino/bf-sde-9.8.0"
SWITCHAROO_TOFINO_SDE_INSTALL="$SWITCHAROO_TOFINO_SDE/install"

while getopts p:c:r: flag
do
    case "${flag}" in
        p) path=${OPTARG};;
        c) configuration=${OPTARG};;
        r) rate=${OPTARG};;
    esac
done

if [ -z "$path" ] || [ -z "$configuration" ] || [ -z "$rate" ]; then
        echo 'You missed some parameters' >&2
        exit 1
fi

echo "$(date +'%m-%d-%y-%T') - Starting experiments with the following parameters: " > log.txt

echo "  Output Directory: $path" >> log.txt
echo "  Traffic Pattern Configuration: $configuration" >> log.txt
echo "  Generator Rate: $rate" >> log.txt
echo "  Table Size: 32768" >> log.txt
echo "  Bloom Size: [128, 65536]" >> log.txt

echo "$(date +'%m-%d-%y-%T') - Deleting logs from `$SWITCHAROO_TOFINO_NAME`..." >> log.txt
sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME "sudo rm -rf $SWITCHAROO_PATH/logs/*"

echo "$(date +'%m-%d-%y-%T') - Deleting logs from `$MCAST_TOFINO_NAME`..." >> log.txt
sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME "sudo rm -rf $MULTICAST_PATH/logs/*"

echo "$(date +'%m-%d-%y-%T') - Deleting fastclick logs from `$GENERATOR_SERVER_NAME`..." >> log.txt
sshpass -p $SERVER_USER_PASS ssh $SERVER_USERNAME@$GENERATOR_SERVER_NAME "echo $SERVER_USER_PASS | sudo -S rm -rf $GENERATOR_PATH/logs/*"

for size in 128 256 512 1024 2048 4096 8192 16384 32768 65536
do  
    echo "$(date +'%m-%d-%y-%T') - Cleaning processes..." >> log.txt
    sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
    sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
    tmux kill-session -t switcharoo-experiments

    echo "$(date +'%m-%d-%y-%T') - Building switcharoo with bloom size ${size}" >> log.txt
    echo "$(date +'%m-%d-%y-%T') - Command: ~/tools/p4_build.sh -DTABLE_SIZE=32768 -DBLOOM_FILTER_SIZE=${size} -DENTRY_TIMEOUT=50000 $SWITCHAROO_PATH/p4src/switcharoo.p4" >> log.txt
    
    sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME SDE=$SWITCHAROO_TOFINO_SDE SDE_INSTALL=$SWITCHAROO_TOFINO_SDE_INSTALL  "~/tools/p4_build.sh -DTABLE_SIZE=32768 -DBLOOM_FILTER_SIZE=${size} -DENTRY_TIMEOUT=50000 $SWITCHAROO_PATH/p4src/switcharoo.p4"
    
    echo "$(date +'%m-%d-%y-%T') - Built!" >> log.txt
    
    sleep 2
    for i in 1 2 3 4 5 6 7 8 9 10
    do
        echo "$(date +'%m-%d-%y-%T') - Cleaning processes..." >> log.txt
        sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
        sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
        tmux kill-session -t switcharoo-experiments

        echo "$(date +'%m-%d-%y-%T') - Size ${size} ~ Start Run ${i}" >> log.txt

        tmux kill-session -t switcharoo-experiments
        tmux new-session -d -s switcharoo-experiments

        tmux select-pane -t 0
        tmux split-window -v -t switcharoo-experiments
        tmux send-keys -t switcharoo-experiments "sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME SDE=$MULTICAST_TOFINO_SDE SDE_INSTALL=$MULTICAST_TOFINO_SDE_INSTALL '$MULTICAST_TOFINO_SDE/run_switchd.sh -p switcharoo_mcast'" Enter

        tmux select-pane -t 0
        tmux split-window -v -t switcharoo-experiments
        tmux send-keys -t switcharoo-experiments "sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME SDE=$MULTICAST_TOFINO_SDE SDE_INSTALL=$MULTICAST_TOFINO_SDE_INSTALL '$MULTICAST_TOFINO_SDE/run_bfshell.sh -i -b $MULTICAST_PATH/setup_$configuration.py'" Enter

        tmux select-pane -t 0
        tmux split-window -v -t switcharoo-experiments
        tmux send-keys -t switcharoo-experiments "sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME SDE=$SWITCHAROO_TOFINO_SDE SDE_INSTALL=$SWITCHAROO_TOFINO_SDE_INSTALL '$SWITCHAROO_TOFINO_SDE/run_switchd.sh -p switcharoo -c $SWITCHAROO_PATH/switcharoo.conf'" Enter

        tmux select-pane -t 0
        tmux split-window -v -t switcharoo-experiments
        tmux send-keys -t switcharoo-experiments "sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME SDE=$SWITCHAROO_TOFINO_SDE SDE_INSTALL=$SWITCHAROO_TOFINO_SDE_INSTALL '$SWITCHAROO_TOFINO_SDE/run_bfshell.sh -i -b $SWITCHAROO_PATH/setup.py'" Enter
        
        tmux select-pane -t 0
        tmux send-keys -t switcharoo-experiments "sshpass -p $SERVER_USER_PASS ssh $SERVER_USERNAME@$GENERATOR_SERVER_NAME -t 'echo sleep; sleep 45; echo $SERVER_USER_PASS | sudo -S mkdir -p $GENERATOR_PATH/logs; cd $GENERATOR_PATH && echo $SERVER_USER_PASS | sudo -S ./gen-rated-mt-lat.sh rate=$rate length=1024; echo $SERVER_USER_PASS | sudo -S mv logs/srv-log.log logs/log-$size-$i.log; sleep 10'; tmux kill-session -t switcharoo-experiments" Enter
        tmux attach -t switcharoo-experiments

        echo "$(date +'%m-%d-%y-%T') - Cleaning processes..." >> log.txt
        sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
        sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME -t "killall -9 run_switchd.sh; killall -9 run_bfshell.sh; killall -9 bfshell; sudo pkill -9 -f 'bf_switchd'"
        tmux kill-session -t switcharoo-experiments
        
        echo "$(date +'%m-%d-%y-%T') - Size ${size} ~ End Run ${i}" >> log.txt

        sleep 5
    done
    echo "$(date +'%m-%d-%y-%T') - End Size ${size}" >> log.txt

    mkdir -p $path/$configuration/$size/switcharoo-logs
    mkdir -p $path/$configuration/$size/mcast-logs
    mkdir -p $path/$configuration/$size/fastclick-logs

    echo "Copying `$SWITCHAROO_TOFINO_NAME` logs in $path/$configuration/$size" >> log.txt
    sshpass -p $TOFINO_USER_PASS scp -r $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME:$SWITCHAROO_PATH/logs/* $path/$configuration/$size/switcharoo-logs

    echo "Deleting logs from `$SWITCHAROO_TOFINO_NAME`..." >> log.txt
    sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$SWITCHAROO_TOFINO_NAME "sudo rm -rf $SWITCHAROO_PATH/logs/*"

    echo "Copying `$MCAST_TOFINO_NAME` logs in $path/$configuration/$size" >> log.txt
    sshpass -p $TOFINO_USER_PASS scp -r $TOFINO_USERNAME@$MCAST_TOFINO_NAME:$MULTICAST_PATH/logs/* $path/$configuration/$size/mcast-logs

    echo "Deleting logs from `$MCAST_TOFINO_NAME`..." >> log.txt
    sshpass -p $TOFINO_USER_PASS ssh $TOFINO_USERNAME@$MCAST_TOFINO_NAME "sudo rm -rf $MULTICAST_PATH/logs/*"

    echo "Copying `$GENERATOR_SERVER_NAME` logs in $path/$configuration/$size" >> log.txt
    sshpass -p $SERVER_USER_PASS scp -r $SERVER_USERNAME@$GENERATOR_SERVER_NAME:$GENERATOR_PATH/logs/* $path/$configuration/$size/fastclick-logs

    echo "Deleting logs from `$GENERATOR_SERVER_NAME`..." >> log.txt
    sshpass -p $SERVER_USER_PASS ssh $SERVER_USERNAME@$GENERATOR_SERVER_NAME "echo $SERVER_USER_PASS | sudo -S rm -rf $GENERATOR_PATH/logs/*"
done