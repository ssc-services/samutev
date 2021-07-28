<!-- TOC -->

- [1. samutev: Salt Multipass Test Vm's](#1-samutev-salt-multipass-test-vms)
    - [1.1. requirements](#11-requirements)
    - [1.2. configuration](#12-configuration)
    - [1.3. usage](#13-usage)
        - [1.3.1. gcp](#131-gcp)
        - [1.3.2. multipass](#132-multipass)
    - [1.4. some details](#14-some-details)
        - [1.4.1. directories](#141-directories)
        - [1.4.2. vm defaults](#142-vm-defaults)
        - [1.4.3. multipass](#143-multipass)
        - [1.4.4. gcp](#144-gcp)
        - [1.4.5. performance](#145-performance)

<!-- /TOC -->

# 1. samutev: Salt Multipass Test Vm's

samutev helps you to deploy [quickly](#145-performance) local test vm's using multipass.

Test-vm's can be deployed either as masterless minion or as a master with minions.  
The resulting test-vm's are preconfigured with working saltstack.  
Inside the test-vm's the salt directories are mapped to /srv/salt/*  

## 1.1. requirements
- a [salt-repo-base-directory ($salt_base)](#12-configuration) with cloned repos `salt-states` and `salt-pillars` of your project inside
- __ubuntu__ 20.04
- __multipass__ (`apt install snapd; snap install multipass`)
- enough __space__ for created vm-disks in `/var`
- enough __memory__ for created vm's - according to application needs
- __internet__ connection (for things like package install)  
- In case of a __vmware-vm__ as multipass host, following settings are needed:  
  ![settings vmware-vm](images/vmware_setting.png)
- In case you want to use __"Google Cloud"__ as a provider backend you need:
  - An account and a project in GCP (with allocated budget)
  - The gcloud cli utility installed (`snap install google-cloud-sdk --classic`)
  - Some additional dependencies installed (`apt-get install -y nfs-kernel-server portmap autossh`)
  - Gcloud configured to use the correct account/project (core/account property): (`gcloud init`)

## 1.2. configuration

If you are working first time with samutev, do once `cp samutev.conf.template samutev.conf`

In `samutev.conf` customize these settings to your need:
1. `salt_base=""`  
should be the directory of your salt project, where git repos `salt-states` and `salt-pillars` reside
2. `my_ssh_pub_key=""`   
used to deploy the ssh-pub-key to each launchend vm to `root` and to the normal user `user`. So you do `ssh root@<vm-ip>` or `ssh user@<vm-ip>`

Further, in `samutev.conf` you can customize [cloudinit](https://cloudinit.readthedocs.io/en/latest/) to bootstrap the vms.

If you intend to use the GCP provider backend you also need to customize 
1. `my_ssh_pub_key=""`  
should be the public SSH key you want to use to connect to the instances
2. `DEFAULT_GCP_ZONE` and `FALLBACK_GCP_MACH_TYPE`   
should not be modified unless you know what/why you are doing 

## 1.3. usage

### 1.3.1. gcp
See section `multipass` - only the default values displayed differ a little.
To use provider `gcp` instead of the default (`multipass`) just prefix the script with `PROVIDER=gcp`:
```
PROVIDER=gcp ./samutev.sh -h 
```

### 1.3.2. multipass
```
Usage:
  ./samutev.sh -h                        display this help message
  ./samutev.sh [-r <release>] -n <VM>    new    <VM> with masterless minion
  ./samutev.sh [-r <release>] -s <VM>    new    <VM> with minion and salt master, first vm => saltmaster, minimum of 2 vms
  ./samutev.sh -d <VM>                   delete <VM>
  ./samutev.sh -l                        list vms

                                         <release>: default is 'lts' aliased to 'focal'
                                         Other available options are:
                                           - 16.04 (or xenial)
                                           - 18.04 (or bionic)
                                           - 20.04 (or focal or lts)

Examples:
  ./samutev.sh -n  testvm                                 launch new testvm            as masterless minion
  ./samutev.sh -n 'testvm1 testvm2 testvm3'               launch multiple new testvms  as masterless minions
  ./samutev.sh -n 'testvm1:c2:m1:d3 testvm2:c4:m2'        launch multiple new testvms  as masterless minions
                                                          with special settings for cpu, memory and disk:
                                                            - testvm1 with: c2 => 2 cpu, m1 => 1GB memory and d3 => 3GB disk
                                                            - testvm2 with: c4 => 4 cpu, m2 => 2GB memory
                                                              (defaults are c2 m1 d3)

  ./samutev.sh -s 'salt-master1 testvm1 testvm2 testvm3'  launch a saltmaster with multiple new testvms
                                                            - First vm = saltmaster
                                                            - Minimum = 2 vms
  ./samutev.sh -s 'salt-master1:c2:m2:d6 testvm1'         same as above but with custom resource settings

  ./samutev.sh -d  testvm                                 delaunch/delete testvm
  ./samutev.sh -d 'testvm1 testvm2 testvm3'               delaunch/delete multiple testvms

```

## 1.4. some details

### 1.4.1. directories
In configured `$salt_base` (`samutev.conf`) two directories will be created, if not already there:
- `localstore/`  -   configured as `file_roots`  
   place to put states or binaries - outside of git repos
- `salt-dev-pillars/devpillars.sls`  -    configured as `pillar_roots`  
   place to put you dev-pillars - outside of git repos

Both directories will be available either to the salt master or to masterless minions directly

### 1.4.2. vm defaults

### 1.4.3. multipass
type | default
-----|--------
cpu | 2
memory | 1 (GB)
disk | 4 (GB)

### 1.4.4. gcp
Type: e2-micro

type | default
-----|--------
cpu | 2
memory | 1 (GB)
disk | 10 (GB)


### 1.4.5. performance
some meassured times, create 4 vm's, 1 salt-master and 3 minions:  
`samutev.sh -s "project-master project-app project-db project-web"`  

__multipass__
environment | time
------------|------
vm Testcluster (4GB RAM)| 10:49 min
Lenovo x390 (16GB RAM)| 04:27 min
Lenovo T14 AMD (32GB RAM)| 03:45 min
Lenoveo P53 (32GB RAM)| 03:31 min

__gcp__
environment | time
------------|------
google cloud| 05:38
