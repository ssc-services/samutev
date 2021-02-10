#!/bin/bash
#
# Script to launch or delaunch multipass (or gcp) vms with masterless minion(s)
# for easy testing of salt states
#
# 2020-10-21 RO
# 2020-11-18 TS
# 2021-02-10 TS added first poc for gcp capability

# default provide is multipass
PROV=${PROVIDER:-multipass}
PROV=${PROV,,}

# set default values for resource settings (applies to help text and code)
C_DEFAULT=2
M_DEFAULT=1
# gcp image minimum is 10G
GCP_MINIMUM_DISK=10
echo "${PROV}" | grep -q '^multipass$' && D_DEFAULT=3 || D_DEFAULT=${GCP_MINIMUM_DISK}

scriptpath=$(readlink -f "${0}")

# shellcheck source=samutev.conf.template
source "${scriptpath%.*}".conf

if [ ! -d "$salt_base" ]; then
  echo
  echo " configured salt_base=\"$salt_base\" not found!"
  echo " please configure a valid directory"
  echo
  exit 23
fi

# MEMORY_GB filter is somehow not working -> resort to grep...
echo "${PROV}" | grep -q '^multipass$' || GCP_DEFAULT=$(gcloud compute machine-types list --filter="CPUS=${C_DEFAULT} AND zone=${DEFAULT_GCP_ZONE}" 2>&1 | grep "$(printf %.2f ${M_DEFAULT} | sed 's@,@.@g')"$ | awk '{ print $1 }')

if [ "${PROV}" != "multipass" ]; then
  echo "$GCP_DEFAULT" | sed '/^$/d' | wc -c | grep -q '^0$' && echo "WARNING: Invalid default compute resource values for gcp, falling back to '${FALLBACK_GCP_MACH_TYPE}'."
  echo "$GCP_DEFAULT" | sed '/^$/d' | wc -c | grep -q '^0$' && GCP_DEFAULT=${FALLBACK_GCP_MACH_TYPE}
fi

echo "${PROV}" | grep -q '^multipass$' && MAIN_DEP=multipass || MAIN_DEP=google-cloud-sdk
echo "${PROV}" | grep -q '^multipass$' && SNAP_PARA="" || SNAP_PARA=" --classic\n Run 'gcloud init' afterwards"

snap list ${MAIN_DEP} >/dev/null 2>&1
RET=$?
if [ ${RET} -ne 0 ]; then
  echo
  echo " please install ${MAIN_DEP} to use samutev with provider $PROV"
  echo -e " =>  snap install ${MAIN_DEP}${SNAP_PARA}"
  echo
  exit 42
fi

# TBD check that gcloud init was done

if [ "${PROV}" != "multipass" -a "$(apt list --installed 2>&1| grep -c -e nfs-kernel-server -e autossh)" != "2" ]; then
  echo
  echo " please install nfs-kernel-server and autossh to use samutev with provider $PROV"
  echo " =>  apt install -y nfs-kernel-server portmap autossh"
  echo
  exit 255
fi

# default value for multipass, latest LTS, currently: "focal"
# default value for gcp, latest LTS, currently *hardcoded* below to focal,minimal,lts -> "ubuntu-minimal-2004-lts"
echo "${PROV}" | grep -q '^multipass$' && \
 CODENAME_OF_LTS=$(multipass find | grep LTS | grep lts | awk '{ print $2 }' | sed 's@,@\n@g' | grep -v lts | tail -n1) \
 || \
 CODENAME_OF_LTS=$(gcloud compute images list --filter="family=ubuntu" | grep lts | grep focal | grep minimal | awk '{ print $3}')

function help() {
  scriptname="$(basename "${0}")"
  echo "Usage:"
  echo "  ${scriptname} -h                        display this help message"
  echo "  ${scriptname} [-r <release>] -n <VM>    new    <VM> with masterless minion"
  echo "  ${scriptname} [-r <release>] -s <VM>    new    <VM> with minion and salt master, first vm => saltmaster, minimum of 2 vms"
  echo "  ${scriptname} -d <VM>                   delete <VM>"
  echo "  ${scriptname} -l                        list vms"
  echo
  echo "                                         <release>: default is 'lts' aliased to '${CODENAME_OF_LTS}'"
  echo "                                         Other available options are:"
  echo "${PROV}" | grep -q '^multipass$' && \
  multipass find | grep LTS | awk '{ print $1" (or "$2")" }' | sed 's@,@ or @g' | sed 's@^@                                           - @g' | sed 's@daily:@@g' || \
  gcloud compute images list --filter="family=ubuntu" | grep -e lts | grep minimal | awk '{ print $3}' | sed 's@^@                                           - @g'
  echo
  echo "Examples:"
  echo "  ${scriptname} -n  testvm                                 launch new testvm            as masterless minion"
  echo "  ${scriptname} -n 'testvm1 testvm2 testvm3'               launch multiple new testvms  as masterless minions"
  echo "  ${scriptname} -n 'testvm1:c2:m1:d3 testvm2:c4:m2'        launch multiple new testvms  as masterless minions"
  echo "                                                          with special settings for cpu, memory and disk:"
  echo "                                                            - testvm1 with: c2 => 2 cpu, m1 => 1GB memory and d3 => 3GB disk"
  echo "                                                            - testvm2 with: c4 => 4 cpu, m2 => 2GB memory"
  echo "                                                              (defaults are c${C_DEFAULT} m${M_DEFAULT} d${D_DEFAULT})"
  echo
  echo "  ${scriptname} -s 'salt-master1 testvm1 testvm2 testvm3'  launch a saltmaster with multiple new testvms"
  echo "                                                            - First vm = saltmaster"
  echo "                                                            - Minimum = 2 vms"
  echo "  ${scriptname} -s 'salt-master1:c2:m2:d6 testvm1'         same as above but with custom resource settings"
  echo
  echo "  ${scriptname} -d  testvm                                 delaunch/delete testvm"
  echo "  ${scriptname} -d 'testvm1 testvm2 testvm3'               delaunch/delete multiple testvms"
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
    echo "${PROV}" | grep -q '^multipass$' && \
    multipass list || \
    gcloud compute instances list
    shift
    ;;
  -r)
    if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
      IMAGE="$2"
      echo "${PROV}" | grep -q '^multipass$' && VALID_IMAGE=$(multipass find | grep LTS | grep -c "${IMAGE}" | grep -q '^0$' && echo not found || echo found) ||\
      VALID_IMAGE=$(gcloud compute images list --filter="family=ubuntu" | grep -e lts | grep minimal | awk '{ print $3}' | grep -c "${IMAGE}" | grep -q '^0$' && echo not found || echo found)

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
  --* | -*=) # unsupported flags
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

echo "${PROV}" | grep -q '^multipass$' && \
IMAGE=$(multipass find | grep LTS | grep "${IMAGE}" | awk '{ print $2 }' | sed 's@,@\n@' | grep -v lts | head -n1) || \
OS_CODENAME=$(gcloud compute images list --filter="family=ubuntu" | grep -e lts | grep minimal | grep "${IMAGE}" | awk '{ print $1 }' | awk -F- '{ print $4 }')

echo "${PROV}" | grep -q '^multipass$' && \
IMAGE_CODE=$(multipass find | grep LTS | grep "${IMAGE}" | awk '{ print $1 }' | sed 's@daily:@@g') || \
IMAGE_CODE=$(echo "$IMAGE" | awk -F- '{ split($3, chars, ""); print chars[1]chars[2]"."chars[3]chars[4] }')

# set positional arguments in their proper place
#eval set -- "$PARAMS"
#echo PARAMS=$PARAMS

function create_test_VMs() {
  # TBD before doing anything: check all names whether they exist already (shared project!)
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
  echo "${PROV}" | grep -q '^multipass$' && sed -i "s@VERSION_CODENAME@$IMAGE@g" tmp_cloudinit.$$ || \
  sed -i "s@VERSION_CODENAME@$OS_CODENAME@g" tmp_cloudinit.$$

  AUTOSSH_MPORT=8000
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

    if [ "${PROV}" != "multipass" ]; then
      GCP_MACH_TYPE=$(gcloud compute machine-types list --filter="CPUS=${CPU} AND zone=${DEFAULT_GCP_ZONE}" 2>&1 | grep "$(printf %.2f "${MEM}" | sed 's@,@.@g')"$ | awk '{ print $1 }')
      echo "$GCP_MACH_TYPE" | sed '/^$/d' | wc -c | grep -q '^0$' && echo "WARNING: Invalid compute resource values for gcp (VM '$VM'), falling back to '${FALLBACK_GCP_MACH_TYPE}'."
      echo "$GCP_MACH_TYPE" | sed '/^$/d' | wc -c | grep -q '^0$' && GCP_MACH_TYPE=${FALLBACK_GCP_MACH_TYPE}
      if [ "$DISK" -lt ${GCP_MINIMUM_DISK} ]; then
        echo "WARNING: Disk size '$DISK' (VM '$VM') is below minimum of '${GCP_MINIMUM_DISK}' (for gcp) using '${GCP_MINIMUM_DISK}' instead"
        DISK=${GCP_MINIMUM_DISK}
      fi
    fi

    echo "launching ${VM} ($TYPE with cpu=$CPU mem=${MEM}G disk=${DISK}G${IMAGE_INFO})"
    echo "${PROV}" | grep -q '^multipass$' && \
    multipass launch --cpus "${CPU}" --disk "${DISK}"G --mem "${MEM}"G --name "${VM}" --cloud-init tmp_cloudinit.$$ "${IMAGE}" || \
    gcloud compute instances create "${VM}" --zone="${DEFAULT_GCP_ZONE}" --machine-type="$GCP_MACH_TYPE" --image-project=ubuntu-os-cloud --image-family="${IMAGE}" --boot-disk-type=pd-standard --boot-disk-size="${DISK}GB" --metadata-from-file user-data=tmp_cloudinit.$$
    RET=$?
    if [ "$TYPE" != "minion" ]; then
      if [ "${PROV}" != "multipass" ]; then
        VMIP=$(gcloud compute instances list --filter="NAME=$VM" | awk '{ print $5 }' | grep -v IP)
        until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${VMIP}" whoami 2>/dev/null; do echo "Waiting for vm to be ready..." && sleep 10; done
        EXEC_CMD_PREFIX="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${VMIP}"

        if [ $RET = 0 ]; then
          # nfs exports
          # backup
          sudo cp -p /etc/exports{,.$$}
          # remove pre-existing entries for $VM
          sudo sed -i "/^.*# samutev .* $VM\$/d" /etc/exports
          # add new exports
          {
            echo "${salt_base}/salt-states  localhost(insecure,rw,sync,no_subtree_check,no_root_squash) # samutev $TYPE $VM"
            echo "${salt_base}/salt-pillars localhost(insecure,rw,sync,no_subtree_check,no_root_squash) # samutev $TYPE $VM"
            echo "${salt_base}/localstore  localhost(insecure,rw,sync,no_subtree_check,no_root_squash) # samutev $TYPE $VM"
            echo "${salt_base}/salt-dev-pillars  localhost(insecure,rw,sync,no_subtree_check,no_root_squash) # samutev $TYPE $VM"
          } >> /tmp/exports.$$

          # In a masterless scenario this is executed multiple times. Adding the same export >1 time makes NFS fail -> do it only once
          grep -q "${salt_base}/salt-states" /etc/exports || sudo bash -c "cat /tmp/exports.$$ >> /etc/exports"
          # set active and remove backup or revert -> TBD terminate (and cleanup?) here when export mgmt fails
          # TBD why does exportfs -a (instead of restart, which would be better) doesn't remove removed exports?
          sudo systemctl restart nfs-kernel-server && sudo rm -f /etc/exports.$$ || sudo cp -p /etc/exports.$$ /etc/exports
        fi
      else
        EXEC_CMD_PREFIX="multipass exec ${VM}"
      fi
      case $TYPE in
      "masterless")
        echo "${PROV}" | grep -q '^multipass$' || autossh -M $AUTOSSH_MPORT -f -N -R 2049:localhost:2049 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${VMIP}"
        AUTOSSH_MPORT=$((AUTOSSH_MPORT+2))
        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-states
        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-pillars

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-states        "${VM}":/srv/salt/salt-states || \
        ${EXEC_CMD_PREFIX} --                         "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo Waiting for cloud-init to finish... && sleep 5; done && mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-states /srv/salt/salt-states"
        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-pillars       "${VM}":/srv/salt/salt-pillars || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-pillars /srv/salt/salt-pillars"

        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/localstore

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/localstore         "${VM}":/srv/salt/localstore || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/localstore /srv/salt/localstore"

        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-dev-pillars

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-dev-pillars   "${VM}":/srv/salt/salt-dev-pillars || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-dev-pillars /srv/salt/salt-dev-pillars"

        ${EXEC_CMD_PREFIX} --                         sudo systemctl restart salt-minion
        ;;
      "minion")
        ${EXEC_CMD_PREFIX} --                         sudo systemctl restart salt-minion
        ;;
      "master")
        echo "${PROV}" | grep -q '^multipass$' || autossh -M $AUTOSSH_MPORT -f -N -R 2049:localhost:2049 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${VMIP}"

        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-states
        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-pillars

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-states        "${VM}":/srv/salt/salt-states || \
        ${EXEC_CMD_PREFIX} --                         "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo Waiting for cloud-init to finish... && sleep 5; done && mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-states /srv/salt/salt-states"
        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-pillars       "${VM}":/srv/salt/salt-pillars || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-pillars /srv/salt/salt-pillars"

        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/localstore

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/localstore         "${VM}":/srv/salt/localstore || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/localstore /srv/salt/localstore"

        ${EXEC_CMD_PREFIX} --                         sudo mkdir -p /srv/salt/salt-dev-pillars

        echo "${PROV}" | grep -q '^multipass$' && multipass mount "${salt_base}"/salt-dev-pillars   "${VM}":/srv/salt/salt-dev-pillars || \
        ${EXEC_CMD_PREFIX} --                         "mount -t nfs -o proto=tcp localhost:\"${salt_base}\"/salt-dev-pillars /srv/salt/salt-dev-pillars"

        ${EXEC_CMD_PREFIX} --                         sudo systemctl restart salt-master
        ;;
      esac
      echo
    fi

    echo "${PROV}" | grep -q '^multipass$' && multipass info "${VM}" || \
    gcloud compute instances describe "${VM}" | grep -e ^name -e natIP -e diskSize -e ubuntu-os-cloud | sed 's@^name:@a_name:@g' | sed 's@^  - https.*licenses/@OS: @g' | sed 's@^ *@@g' | sort | sed 's@^a_@@g'
    duration=$SECONDS
    echo "launched  ${VM} in $(($duration / 60)) minutes and $(($duration % 60)) seconds."
    echo
  done
  rm -f tmp_cloudinit.$$
  echo
}

function delete_and_purge_VMs() {
  # TBD cleanup /etc/exports when using gcp (upon recreation there is a cleanup -> so low prio for now)
  time_start=$(date +%s)
  for VMin in ${1}; do
    SECONDS=0
    VM=${VMin%%:*}
    echo "delaunching $VM"
    echo
    echo "${PROV}" | grep -q '^multipass$' && multipass delete "${VM}" || \
    gcloud compute instances delete -q --delete-disks=all "${VM}"
    if [ "${PROV}" != "multipass" ]; then
      killall autossh > /dev/null 2>&1
      sudo cp -p /etc/exports{,_preremove.$$}
      sudo sed -i "/^.*# samutev .* $VM\$/d" /etc/exports
      sudo systemctl restart nfs-kernel-server && sudo rm -f /etc/exports_preremove.$$ || sudo cp -p /etc/exports_preremove.$$ /etc/exports
    fi
    duration=$SECONDS
    echo "delaunched  $VM in $((duration / 60)) minutes and $((duration % 60)) seconds."
    echo
  done
  echo "${PROV}" | grep -q '^multipass$' && multipass purge
  time_end=$(date +%s)
  alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
  echo "alltogether: $alltogether min."
  echo
  echo "${PROV}" | grep -q '^multipass$' && multipass list || \
  gcloud compute instances list
  echo
}

# --- main
# make sure there is no trailing / - important for some NFS export operations
salt_base=$(echo "${salt_base}" | sed 's@/$@@g')
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
  echo
  echo "${PROV}" | grep -q '^multipass$' || \
  echo -e "HINT: ssh tunnels are not maintained across reboots yet - re-establish them after reboot by running (foreach IP in <master IP or masterless minion IPs>):\n  $(ps -ef | grep [a]utossh | sed 's@^.*/autossh@autossh -f@g' | grep "root")"
fi

if [ -n "${MasterVMs_2_CREATE+x}" ]; then
  time_start=$(date +%s)
  MASTER=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f1)
  MINION=$(echo "$MasterVMs_2_CREATE" | head -n1 | cut -d ' ' -f2-)
  create_test_VMs master "${MASTER}"
  echo "${PROV}" | grep -q '^multipass$' && NEW_MASTER_IP=$(multipass info "${MASTER%%:*}" | grep IPv4 | awk -F: '{print $2}' | xargs) || \
  NEW_MASTER_IP=$(gcloud compute instances list --filter="NAME=$VM" | awk '{ print $5 }' | grep -v IP)
  #echo NEW_MASTER_IP=$NEW_MASTER_IP
  create_test_VMs minion "${MINION}" "$NEW_MASTER_IP"

  MINION_CTR=$(for VMinput in ${MINION}; do VM="${VMinput//:*/}" ; echo "${VM}"; done | wc -l)
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$NEW_MASTER_IP" 'while [ "$(find /etc/salt/pki/master/minions_pre/ -type f | wc -l)" != "'"${MINION_CTR}"'" ]; do echo Waiting for minions... && sleep 5; done; salt-key -A -y && echo && salt-key -L'

  time_end=$(date +%s)
  alltogether=$(date -d "0 $time_end seconds - $time_start seconds" +'%M:%S')
  echo
  echo "alltogether: $alltogether min."

  echo
  echo "READY to go:"
  echo "    ssh root@$NEW_MASTER_IP"
  echo "    salt '*' test.ping"
  echo
  # TBD improve this
  echo "${PROV}" | grep -q '^multipass$' || \
  echo -e "HINT: ssh tunnels are not maintained across reboots yet - re-establish them after reboot by running (foreach IP in <master IP or masterless minion IPs>):\n  $(ps -ef | grep [a]utossh | sed 's@^.*/autossh@autossh -f@g' | grep "root")"
fi

if [ -n "${VMs_2_DELETE+x}" ]; then
  delete_and_purge_VMs "$VMs_2_DELETE"
fi

# cleanup
rm -f tmp_cloudinit.*
