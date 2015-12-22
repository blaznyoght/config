#!/bin/sh

# Partition disks
#################

cat << EOF | sfdisk --force /dev/sda
# partition table of /dev/sda
unit: sectors

/dev/sda1 : start=     4096, size= 40957952, Id=83, bootable
/dev/sda2 : start= 40962048, size=  2095104, Id=82
/dev/sda3 : start= 43057152, size=784334848, Id=8e
/dev/sda4 : start=827392000, size=149381168, Id=8e
EOF

partprobe

# Setup main volumes
####################

pvcreate -f /dev/sda3
vgcreate vg-main /dev/sda3
lvcreate -L 150G -n home vg-main
lvcreate -L 50G -n var vg-main
#lvcreate -L 50G -n usr vg-main

mkswap /dev/sda2
mkfs.ext4 /dev/vg-main/home
mkfs.ext4 /dev/vg-main/var
#mkfs.ext4 /dev/vg-main/usr

mkdir /tmp/tmpmnt
# Transfer files: usr
#mount /dev/vg-main/usr /tmp/tmpmnt
#rsync -av /usr/ /tmp/tmpmnt
#umount /tmp/tmpmnt
# Transfer files: var
mount /dev/vg-main/var /tmp/tmpmnt
rsync -av /var/ /tmp/tmpmnt
umount /tmp/tmpmnt
# Transfer files: home
mount /dev/vg-main/home /tmp/tmpmnt
rsync -av /home/ /tmp/tmpmnt
umount /tmp/tmpmnt


# Setup docker volumes
######################
pvcreate /dev/sda4
vgcreate vg-docker /dev/sda4
lvcreate -L 4G -n metadata vg-docker
lvcreate -L 67G -n data vg-docker

# Setup fstab
#############
mv /etc/fstab /etc/fstab.bak
cat << EOF > /etc/fstab
#  <file system>	<mount point>	<type>	<options>	<dump>	<pass>
/dev/sda1 / ext4 errors=remount-ro 0 1
/dev/sda2 swap swap	defaults 0 0
/dev/vg-main/home /home ext4 defaults 1 2
/dev/vg-main/var /var ext4 defaults 1 2
#/dev/vg-main/usr /usr ext4 defaults 1 2
proc /proc proc defaults 0	0
sysfs /sys sysfs defaults 0 0
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
EOF

#mount /usr
mount /var
mount /home

yum update

yum install -y zsh

# Docker Setup
##############
tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

yum install -y docker-engine

#sed -i '/\[Service\]/ a EnvironmentFile=-/etc/sysconfig/docker-storage' /usr/lib/systemd/system/docker.service
#sed -i '/\[Service\]/ a EnvironmentFile=-/etc/sysconfig/docker-network' /usr/lib/systemd/system/docker.service
#sed -i '/\[Service\]/ a EnvironmentFile=-/etc/sysconfig/docker' /usr/lib/systemd/system/docker.service
#sed -i 's/fd:\/\//fd:\/\/ \$OPTIONS \\/' /usr/lib/systemd/system/docker.service
#sed -i '/\$OPTIONS \\/ a \\t$DOCKER_STORAGE_OPTIONS \\\n\t$DOCKER_NETWORK_OPTIONS \\\n\t$BLOCK_REGISTRY \\\n\t$INSECURE_REGISTRY' /usr/lib/systemd/system/docker.service
#
mkdir /etc/systemd/system/docker.service.d

cat << EOF > /etc/systemd/system/docker.service.d
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target docker.socket
Requires=docker.socket
[Service]
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-network
EnvironmentFile=-/etc/sysconfig/docker-storage
Type=notify
ExecStart=/usr/bin/docker daemon -H fd:// $OPTIONS \
        $DOCKER_STORAGE_OPTIONS \
        $DOCKER_NETWORK_OPTIONS \
        $BLOCK_REGISTRY \
        $INSECURE_REGISTRY
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/sysconfig/docker-storage
DOCKER_STORAGE_OPTIONS="--storage-driver=devicemapper --storage-opt dm.datadev=/dev/vg-docker/data --storage-opt dm.metadatadev=/dev/vg-docker/metadata"
EOF

systemctl daemon-reload

systemctl enable docker

# Setup User
############
useradd -m -G wheel -s /usr/bin/zsh blaz

mkdir /home/blaz/.ssh
cat << EOF > /home/blaz/.ssh/authorized_keys2
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDDsf9AJoKMwASt2ekFiwysP9mVSpODPzFLJ298U9RAFFI902Mt4mpQuFVB7w0M74HjneTIDIOjstNlYnCeS2aMOtKcjnmLciqd4wtEAoh26C2S9JUzdqm6oQZYb1C21JirNqBtIZ6gGUlE8NmkcVa9ODD1wHDp608lidLoFPDSEePM29c4SSMvoXR3TCqRwFeX+WhfzmdQZh5bASfwQpLm4Qn2e12h93TjQm0Q/AdxEHagnhyWR9jTOtnf5Mo/X5pLJc2dh859Vh/1xTZudgrCHF5n4rMzrG7zC7AlkL6l+NR41wfksUhT7tNuhcpVTHGDbyCmZsQrZClmhECkq5T blaznyoght@MacBook-Pro-de-Pierre-Yves.local
EOF

cat << EOF > /home/blaz/.ssh/authorized_keys2
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCo7wH+kaPtgPSvWsUqat9OzYxteG8FoyZR8lxWiW+LrJ9vpweVmGndyiztweJBk75Iqj3rHeuB1kSsP3f6rNn8+veyp7QX/ExxraOf3fAlw17x3vXSvvDrB12cdbmN7j3V6R0DfwUshsSWd+Nid5T2gtXr3UR8CfZ2PANq4Sf82F9DMX9iW1Cg4XBsn6cFxeL4blJDL5IQ9D4kJhAlqDRefe2Edl+tjtsukd1Z6M28KOWPDdFuO1aqx6qlWa6TuM38PV4soiDTr7h61DhHjQgEMnV98xHYAn4KRAgfhGY3EN9t25LIHUJ4hH6Hmba8RYQUJK4YgHzsdhInwoSLJ pyaillet@ITEM-87245
EOF

reboot