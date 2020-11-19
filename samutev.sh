#!/bin/bash
#
# Script to launch or delaunch multipass vms with masterless minion(s)
# for easy testing of salt states
#
# 2020-10-21 RO
# 2020-11-18 TS

# set default values for resource settings (applies to help text and code)
C_DEFAULT=2
M_DEFAULT=1
D_DEFAULT=3

f=$0
f=${f##*/}
f=${f%.*}
. "$f".conf

if [ ! -d "$salt_base" ]; then
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

CODENAME_OF_LTS=$(multipass find | grep LTS | grep lts | awk '{ print $2 }' | sed 's@,@\n@g' | grep -v lts | tail -n1)

function help() {
  echo -e "Usage:"
  echo -e "\t$0 -h \t\t\t Display this help message"
  echo -e "\t$0 [-r <release>] -n <VM> \t new \t <VM> with masterless minion"
  echo -e "\t$0 [-r <release>] -s <VM> \t new \t <VM> with minion and salt master, first vm => saltmaster, minimum of 2 vms"
  echo -e "\t$0 -d <VM> \t\t\t delete\t <VM>"
  echo -e "\t$0 -l \t\t\t list vms"
  echo
  echo -e "\t\t\t\t\t\t <release>: default is 'lts' aliased to '${CODENAME_OF_LTS}'"
  echo -e "\t\t\t\t\t\t Other available options are:"
  echo -e "$(multipass find | grep LTS | awk '{ print $1" (or "$2")" }' | sed 's@,@ or @g' | sed 's@^@\t\t\t\t\t\t\t - @g' | sed 's@daily:@@g')"
  echo
  echo -e "Examples:"
  echo -e "\t$0 -n  testvm \t\t\t\t launch new testvm \t\t as masterless minion"
  echo -e "\t$0 -n 'testvm1 testvm2 testvm3' \t\t launch multiple new testvms \t as masterless minions"
  echo -e "\t$0 -n 'testvm1:c2:m1:d3 testvm2:c4:m2' \t launch multiple new testvms \t as masterless minions"
  echo -e "\t\t\t\t\t\t\t\t with special settings for cpu, memory and disk:"
  echo -e "\t\t\t\t\t\t\t\t\t - testvm1 with: c2 => 2 cpu, m1 => 1GB memory and d3 => 3GB disk"
  echo -e "\t\t\t\t\t\t\t\t\t - testvm2 with: c4 => 4 cpu, m2 => 2GB memory"
  echo -e "\t\t\t\t\t\t\t\t\t   (defaults are c${C_DEFAULT} m${M_DEFAULT} d${D_DEFAULT})"
  echo
  echo -e "\t$0 -s 'salt-master1 testvm1 testvm2 testvm3' \t launch a saltmaster with multiple new testvms"
  echo -e "\t\t\t\t\t\t\t\t\t - First vm = saltmaster"
  echo -e "\t\t\t\t\t\t\t\t\t - Minimum = 2 vms"
  echo -e "\t$0 -s 'salt-master1:c2:m2:d6 testvm1' \t same as above but with custom resource settings"
  echo
  echo -e "\t$0 -d  testvm \t\t\t\t delaunch/delete testvm"
  echo -e "\t$0 -d 'testvm1 testvm2 testvm3' \t\t delaunch/delete multiple testvms"
  echo
}

# Parse options
#PARAMS=""

IMAGE=""
IMAGE_INFO=""
IMAGE_CODE=""
unset MasterlessVMs_2_CREATE MasterVMs_2_CREATE VMs_2_DELETE
while (("$#")); do
  case "$1" in
  -h | --help)
    help
    exit 0
    ;;
  -n | --new)
    if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
      MasterlessVMs_2_CREATE=$2
      shift 2
    else
      echo "Error: Argument for $1 is missing" >&2
      exit 1
    fi
    ;;
  -s | --new-with-saltmaster)
    if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
      MasterVMs_2_CREATE=$2
      counter=0
      for i in $MasterVMs_2_CREATE; do counter=$((counter + 1)); done
      if [ $counter -lt 2 ]; then
        echo "Error: need minimum 2 vms - 1 saltmaster-vm and 1 minion-vm"
        exit 2
      fi
      shift 2
    else
      echo "Error: Argument for $1 is missing" >&2
      exit 1
    fi
    ;;
  -d | --delete)
    if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
      VMs_2_DELETE=$2
      shift 2
    else
      echo "Error: Argument for $1 is missing" >&2
      exit 1
    fi
    ;;
  -l | --list)
    multipass list
    shift
    ;;
  -r)
    if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
      IMAGE="$2"
      VALID_IMAGE=$(multipass find | grep LTS | grep -c "${IMAGE}" | grep -q '^0$' && echo not found || echo found)
      if [ "${VALID_IMAGE}" == "not found" ]; then
        echo "Error: Argument '${IMAGE}' for $1 is invalid" >&2
        exit 2
      fi
      shift 2
    else
      echo "Error: Argument for $1 is missing" >&2
      exit 1
    fi
    ;;
  -* | --*=) # unsupported flags
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

IMAGE=${IMAGE:-${CODENAME_OF_LTS}}
IMAGE_INFO=" and image '${IMAGE}'"
echo "${IMAGE}" | grep -c lts | grep -q '^1$' && IMAGE=${CODENAME_OF_LTS}
IMAGE=$(multipass find | grep LTS | grep "${IMAGE}" | awk '{ print $2 }' | sed 's@,@\n@' | grep -v lts | head -n1)
IMAGE_CODE=$(multipass find | grep LTS | grep "${IMAGE}" | awk '{ print $1 }' | sed 's@daily:@@g')

# set positional arguments in their proper place
#eval set -- "$PARAMS"
#echo PARAMS=$PARAMS

function create_test_VMs() {
  TYPE=$1
  VMs="$2"
  if [ "xxx${3}xxx" != "xxxxxx" ]; then MASTER_IP="$3"; fi

  # build needed cloudinit-file
  case $TYPE in
  "masterless")
    echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_masterless" "$CLOUDINIT_3_user" > tmp_cloudinit.$$
    ;;
  "minion")
    echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_minion" "$CLOUDINIT_3_user" | sed -e "s/xxxIPxxx/$MASTER_IP/" > tmp_cloudinit.$$
    ;;
  "master")
    echo "$CLOUDINIT_1_header" "$CLOUDINIT_2_master" "$CLOUDINIT_3_user" > tmp_cloudinit.$$
    ;;
  esac

  # switch cloud-init config as $RELEASE variables et al sadly seem to be not yet available in this cloudinit version
  sed -i "s@VERSION_ID@$IMAGE_CODE@g" tmp_cloudinit.$$
  sed -i "s@VERSION_CODENAME@$IMAGE@g" tmp_cloudinit.$$

  # create VMs
  for VMinput in $VMs; do
    SECONDS=0
    unset aCPU CPU aMEM MEM aDISK DISK
    VM="${VMinput//:*/}"
    if echo "$VMinput" | grep -q :; then
      for i in $(echo "${VMinput#*:}" | sed -e "s/:/ /g"); do
        case $i in
        c*)
          aCPU=${i/c/}
          ;;
        m*)
          aMEM=${i/m/}
          ;;
        d*)
          aDISK=${i/d/}
          ;;
        esac
      done
    fi
    CPU=${aCPU:-$C_DEFAULT}
    MEM=${aMEM:-$M_DEFAULT}
    DISK=${aDISK:-$D_DEFAULT}

    echo "launching ${VM} ($TYPE with cpu=$CPU mem=${MEM}G disk=${DISK}G${IMAGE_INFO})"
    multipass launch --cpus "${CPU}" --disk "${DISK}"G --mem "${MEM}"G --name "${VM}" --cloud-init tmp_cloudinit.$$ ${IMAGE}
    RET=$?
    if [ $RET = 0 ]; then
      case $TYPE in
      "masterless")
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-states
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-pillars
        multipass mount "${salt_base}"/salt-states        "${VM}":/srv/salt/salt-states
        multipass mount "${salt_base}"/salt-pillars       "${VM}":/srv/salt/salt-pillars
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/localstore
        multipass mount "${salt_base}"/localstore         "${VM}":/srv/salt/localstore
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-dev-pillars
        multipass mount "${salt_base}"/salt-dev-pillars   "${VM}":/srv/salt/salt-dev-pillars
        multipass exec "${VM}" --                         sudo systemctl restart salt-minion
        ;;
      "minion")

        multipass exec "${VM}" --                         sudo systemctl restart salt-minion
        ;;
      "master")
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-states
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-pillars
        multipass mount "${salt_base}"/salt-states        "${VM}":/srv/salt/salt-states
        multipass mount "${salt_base}"/salt-pillars       "${VM}":/srv/salt/salt-pillars
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/localstore
        multipass mount "${salt_base}"/localstore         "${VM}":/srv/salt/localstore
        multipass exec "${VM}" --                         sudo mkdir -p /srv/salt/salt-dev-pillars
        multipass mount "${salt_base}"/salt-dev-pillars   "${VM}":/srv/salt/salt-dev-pillars
        multipass exec "${VM}" --                         sudo systemctl restart salt-master
        ;;
      esac
      echo
    fi

    multipass info "${VM}"
    duration=$SECONDS
    echo "launched  ${VM} in $(($duration / 60)) minutes and $(($duration % 60)) seconds."
    echo
  done
  rm -f tmp_cloudinit.$$
  echo
}

function delete_and_purge_VMs() {
  time_start=$(date +%s)
  for VMin in ${1}; do
    SECONDS=0
    VM=${VMin%%:*}
    echo "delaunching $VM"
    echo
    multipass delete "${VM}"
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

if [ ! -d "${salt_base}"/salt-dev-pillars ]; then mkdir "${salt_base}"/salt-dev-pillars; fi
if [ ! -f "${salt_base}"/salt-dev-pillars/top.sls ]; then echo "$DEVPILLARS_top" > "${salt_base}"/salt-dev-pillars/top.sls; fi
if [ ! -f "${salt_base}"/salt-dev-pillars/devpillars.sls ]; then echo "$DEVPILLARS" > "${salt_base}"/salt-dev-pillars/devpillars.sls; fi
if [ ! -d "${salt_base}"/localstore ]; then mkdir "${salt_base}"/localstore; fi

if [ -n "${MasterlessVMs_2_CREATE+x}" ]; then
  time_start=$(date +%s)
  create_test_VMs masterless "${MasterlessVMs_2_CREATE}"
  time_end=$(date +%s)
  alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
  echo "alltogether: $alltogether min."
fi

if [ -n "${MasterVMs_2_CREATE+x}" ]; then
  time_start=$(date +%s)
  MASTER=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f1)
  MINION=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f2-)
  create_test_VMs master "${MASTER}"
  NEW_MASTER_IP=$(multipass info "${MASTER%%:*}" | grep IPv4 | awk -F: '{print $2}' | xargs)
  #echo NEW_MASTER_IP=$NEW_MASTER_IP
  create_test_VMs minion "${MINION}" "$NEW_MASTER_IP"
  ssh -o StrictHostKeyChecking=no root@"$NEW_MASTER_IP" 'salt-key -A -y; echo; salt-key -L'

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

if [ -n "${VMs_2_DELETE+x}" ]; then
  delete_and_purge_VMs "$VMs_2_DELETE"
fi

# cleanup
rm -f tmp_cloudinit.*
