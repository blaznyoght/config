#!/bin/sh

# Partition disks
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
pvcreate -f /dev/sda3
vgcreate vg-main /dev/sda3
lvcreate -L 150G -n home vg-main
lvcreate -L 50G -n var vg-main
lvcreate -L 50G -n usr vg-main

mkswap /dev/sda2
mkfs.ext4 /dev/vg-main/home
mkfs.ext4 /dev/vg-main/var
mkfs.ext4 /dev/vg-main/usr

# Transfer files: usr
mkdir /tmp/tmpmnt
mount /dev/vg-main/usr /tmp/tmpmnt
rsync -av /usr/ /tmp/tmpmnt
umount /tmp/tmpmnt
# Transfer files: var
mount /dev/vg-main/var /tmp/tmpmnt
rsync -av /var/ /tmp/tmpmnt
umount /tmp/tmpmnt
# Transfer files: home
mount /dev/vg-main/home /tmp/tmpmnt
rsync -av /home/ /tmp/tmpmnt
umount /tmp/tmpmnt

# Setup docker volumes
pvcreate /dev/sda4
vgcreate vg-docker /dev/sda4
lvcreate -L 4G -n metadata vg-docker
lvcreate -L 67G -n data vg-docker

# Setup fstab
mv /etc/fstab /etc/fstab.bak
cat << EOF > /etc/fstab
#  <file system>	<mount point>	<type>	<options>	<dump>	<pass>
/dev/sda1 / ext4 errors=remount-ro 0 1
/dev/sda2 swap swap	defaults 0 0
/dev/vg-main/home /home ext4 defaults 1 2
/dev/vg-main/var /var ext4 defaults 1 2
/dev/vg-main/usr /usr ext4 defaults 1 2
proc /proc proc defaults 0	0
sysfs /sys sysfs defaults 0 0
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
EOF