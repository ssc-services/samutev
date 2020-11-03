#!/bin/bash
#
# Script to launch or delaunch multipass vm's with masterless minion
#        to easy test salt states
#
# 2020-10-21 RO
#


f=$0 ; f=${f##*/}; f=${f%.*}
. $f.conf

if [ ! -d $salt_base ]; then
  echo
  echo " configured salt_base=\"$salt_base\" not found!"
  echo " please configure a valid directory"
  echo
  exit 23
fi

snap list multipass >/dev/null 2>&1
RET=$?
if [ ${RET} -ne 0 ]; then
  echo
  echo " please install multipass to use samutev"
  echo " =>  snap install multipass"
  echo
  exit 42
fi

function help {
      echo "Usage:"
      echo "    $0 -h               Display this help message."
      echo "    $0 -n <VM>          new <VM> with masterless minion"
      echo "    $0 -s <VM>          new <VM> with minion and salt master. FIRST vm=saltmaster. minimum 2 vm's"
      echo "    $0 -d <VM>          delete <VM>"
      echo "    $0 -l               list   VM's"
      echo
      echo "Examples:"
      echo "    $0 -n  testvm                                launch new testvm              as masterless minion"
      echo "    $0 -n 'testvm1 testvm2 testvm3'              launch multiple new testvm's   as masterless minions"
      echo "    $0 -n 'testvm1:c2:m1:d3 testvm2:c4:m2'  launch multiple new testvm's   as masterless minions"
      echo "                                            with special settings for cpu, memory and disk"
      echo "                                            testvm1 with 2 cpu, 1GB memory and 3GB disk"
      echo "                                            defaults are c2 m1 d3"
      echo
      echo "    $0 -s 'salt-master1 testvm1 testvm2 testvm3'"
      echo "                                        launch a saltmaster with multiple new testvm's"
      echo "                                        FIRST vm = saltmaster"
      echo "                                        minimum = 2 vm's"
      echo "    $0 -s 'salt-master1:c2:m2:d6 testvm1'"
      echo
      echo "    $0 -d  testvm                       delaunch/delete testvm"
      echo "    $0 -d 'testvm1 testvm2 testvm3'     delaunch/delete multiple testvm's"
      echo
}

# Parse options 
PARAMS=""
unset MasterlessVMs_2_CREATE MasterVMs_2_CREATE VMs_2_DELETE
while (( "$#" )); do
  case "$1" in
    -h|--help)
      help
      exit 0
      ;;
    -n|--new)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        MasterlessVMs_2_CREATE=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -s|--new-with-saltmaster)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        MasterVMs_2_CREATE=$2
        counter=0; for i in $MasterVMs_2_CREATE; do counter=$((counter+1)); done
        if [ $counter -lt 2 ]; then
          echo "Error: need minimum 2 vm's - 1 saltmaster-vm and 1 minion-vm"
          exit 2
        fi
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -d|--delete)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        VMs_2_DELETE=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -l|--list)
        multipass list
        shift
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      echo
      help
      exit 1
      ;;
    *) # preserve positional arguments
      #PARAMS="$PARAMS $1"
      #shift
      help
      exit 0
      ;;
  esac
done
# set positional arguments in their proper place
#eval set -- "$PARAMS"
#echo PARAMS=$PARAMS

function create_test_VMs {
  TYPE=$1
	VMs="$2"
  if [ "xxx${3}xxx" != "xxxxxx" ]; then MASTER_IP="$3"; fi

  

  # build needed cloudinit-file
  case $TYPE in
    "masterless" )
            echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_masterless" "$CLOUDINIT_3_user" > tmp_cloudinit.$$
            ;;
        "minion" ) 
            echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_minion" "$CLOUDINIT_3_user" | sed -e "s/xxxIPxxx/$MASTER_IP/" > tmp_cloudinit.$$
            ;;            
		    "master" ) 
            echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_master" "$CLOUDINIT_3_user" > tmp_cloudinit.$$
            ;;
  esac

  # create VMs
	for VMinput in $VMs; do
		SECONDS=0
    unset aCPU CPU aMEM MEM aDISK DISK
    VM=$(echo $VMinput | sed -e "s/:.*//")
    echo $VMinput | grep : 2>&1 > /dev/null
    if [ $? = 0 ]; then
      for i in $(echo ${VMinput#*:}|sed -e "s/:/ /g"); do
        case $i in
          c*) aCPU=${i/c/}
              ;;
          m*) aMEM=${i/m/}
              ;;
          d*) aDISK=${i/d/}
              ;;
        esac
      done
    fi
    CPU=${aCPU:-2}
    MEM=${aMEM:-1}
    DISK=${aDISK:-3}

		echo "launching ${VM} ($TYPE with cpu=$CPU mem=${MEM}G disk=${DISK}G)"
		multipass launch --cpus ${CPU} --disk ${DISK}G --mem ${MEM}G --name ${VM} --cloud-init tmp_cloudinit.$$
    RET=$?
    if [ $RET = 0 ]; then
      case $TYPE in
      "masterless" )
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-states
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-pillars
              multipass mount ${salt_base}/salt-states      ${VM}:/srv/salt/salt-states
              multipass mount ${salt_base}/salt-pillars     ${VM}:/srv/salt/salt-pillars
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/localstore
              multipass mount ${salt_base}/localstore       ${VM}:/srv/salt/localstore            
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-dev-pillars
              multipass mount ${salt_base}/salt-dev-pillars ${VM}:/srv/salt/salt-dev-pillars    
              multipass exec ${VM} -- sudo systemctl restart salt-minion
              ;;
          "minion" ) 

              multipass exec ${VM} -- sudo systemctl restart salt-minion
              ;;            
          "master" ) 
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-states
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-pillars
              multipass mount ${salt_base}/salt-states      ${VM}:/srv/salt/salt-states
              multipass mount ${salt_base}/salt-pillars     ${VM}:/srv/salt/salt-pillars
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/localstore
              multipass mount ${salt_base}/localstore       ${VM}:/srv/salt/localstore 
              multipass exec ${VM} -- sudo               mkdir -p /srv/salt/salt-dev-pillars
              multipass mount ${salt_base}/salt-dev-pillars ${VM}:/srv/salt/salt-dev-pillars               
              multipass exec ${VM} -- sudo systemctl restart salt-master
              ;;
      esac
		echo
    fi
    
		multipass info ${VM}
		duration=$SECONDS
		echo "launched  ${VM} in $(($duration / 60)) minutes and $(($duration % 60)) seconds."
		echo
	done
	rm -f tmp_cloudinit.$$
	echo
}

function delete_and_purge_VMs {
	time_start=$(date +%s)
	for VMin in ${1}; do
		SECONDS=0
    VM=${VMin%%:*}
		echo "delaunching $VM"
		echo
		multipass delete ${VM}
		duration=$SECONDS
		echo "delaunched  $VM in $(($duration / 60)) minutes and $(($duration % 60)) seconds."
		echo
	done
	multipass purge
	time_end=$(date +%s)
	alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
	echo "alltogether: $alltogether min."
	echo
	multipass list
	echo
}

# --- main

if [ ! -d ${salt_base}/salt-dev-pillars ];                then mkdir ${salt_base}/salt-dev-pillars; fi
if [ ! -f ${salt_base}/salt-dev-pillars/top.sls ];        then echo "$DEVPILLARS_top" > ${salt_base}/salt-dev-pillars/top.sls; fi
if [ ! -f ${salt_base}/salt-dev-pillars/devpillars.sls ]; then echo "$DEVPILLARS"     > ${salt_base}/salt-dev-pillars/devpillars.sls; fi
if [ ! -d ${salt_base}/localstore ];                      then mkdir ${salt_base}/localstore; fi

if [ ! -z ${MasterlessVMs_2_CREATE+x} ]; then
  time_start=$(date +%s)
	create_test_VMs masterless "${MasterlessVMs_2_CREATE}"
  time_end=$(date +%s)
	alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
	echo "alltogether: $alltogether min."
fi

if [ ! -z ${MasterVMs_2_CREATE+x} ]; then
  time_start=$(date +%s)
  MASTER=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f1) 
  MINION=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f2-)
	create_test_VMs master "${MASTER}"
  NEW_MASTER_IP=$(multipass info ${MASTER%%:*}|grep IPv4|awk -F: '{print $2}'|xargs)
  #echo NEW_MASTER_IP=$NEW_MASTER_IP
  create_test_VMs minion "${MINION}" "$NEW_MASTER_IP"
  ssh -o StrictHostKeyChecking=no root@$NEW_MASTER_IP 'salt-key -A -y; echo; salt-key -L'
  
  time_end=$(date +%s)
	alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
  echo
	echo "alltogether: $alltogether min."  

  echo
  echo "READY to go:"
  echo "    ssh root@$NEW_MASTER_IP"
  echo "    salt '*' test.ping"
  echo
fi

if [ ! -z ${VMs_2_DELETE+x} ]; then
	delete_and_purge_VMs "$VMs_2_DELETE"
fi

# cleanup
rm -f tmp_cloudinit.*
