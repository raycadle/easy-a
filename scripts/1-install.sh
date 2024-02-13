#!/usr/bin/env bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
FUNCTIONS="${SCRIPT_DIR}/helpers/functions.sh"

source "${FUNCTIONS}"

echo -e "-------------------------------------------------
                First Stage: Install
-------------------------------------------------

Starting..."
timedatectl set-ntp true
pacman -Sy --noconfirm --needed pacman-contrib reflector gptfdisk cryptsetup rsync
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
reflector -a 48 -c "${ISO}" -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist

echo -e "-------------------------------------------------
                Disk Preparation
-------------------------------------------------
"
select_disk

if [[ "${DISK}" =~ "nvme" ]]; then # Checking for nvme drives
    declare -r PART1=${DISK}p1
    declare -rx PART2=${DISK}p2
else
    declare -r PART1=${DISK}1
    declare -rx PART2=${DISK}2
fi

sgdisk -Z "${DISK}" # Zap all on disk
sgdisk -a 2048 -o "${DISK}" # New GPT disk with 2048 alignment

if [[ "${SSD}" -eq 0 ]]; then # Disabled if using an SSD, as it can take long to finish due to the way SSDs work.
    cryptsetup open --type plain -d /dev/urandom "${DISK}" to_wipe
    dd if=/dev/zero of=/dev/mapper/to_wipe status=progress # Wiping container
    cryptsetup close to_wipe # Closing container
fi
if [[ -d "/sys/firmware/efi" ]]; then # Checking for UEFI systems
    sgdisk -n 1::+1G --typecode=1:ef00 "${DISK}" # Partition 1 (UEFI Boot, 1GB)
    mkfs.vfat -F32 "${PART1}"
else
    sgdisk -n 1::+1G --typecode=1:ef02 "${DISK}" # Partition 1 (BIOS Boot, 1GB)
    sgdisk -A 1:set:2 "${DISK}" # Setting Partition 1 legacy(BIOS) bootable
    mkfs.ext4 "${PART1}"
fi

sgdisk -n 2::-0 --typecode=2:8300 "${DISK}" # Partition 3 (Root, Remaining space)

cryptsetup --type luks2 --cipher aes-xts-plain64 --hash sha512 --iter-time 10000 --key-size 512 --pbkdf argon2id --use-urandom -y -v luksFormat "${PART2}"
cryptsetup open "${PART2}" cryptroot # Opening container

mkdir -p /mnt/{boot,usr,var/tmp,var/log/audit,home,tmp}
pvcreate /dev/mapper/cryptroot
vgcreate cryptlv /dev/mapper/cryptroot
lvcreate -L 8G cryptlv -n swap; mkswap /dev/cryptlv/swap; swapon /dev/cryptlv/swap
lvcreate -l 10%VG cryptlv -n root; mkfs.ext4 /dev/cryptlv/root; mount -t ext4 /dev/cryptlv/root /mnt -o relatime,errors=remount-ro
lvcreate -l 10%VG cryptlv -n usr; mkfs.ext4 /dev/cryptlv/usr; mount -t ext4 /dev/cryptlv/usr /mnt/usr -o relatime,nodev
lvcreate -l 10%VG cryptlv -n var; mkfs.ext4 /dev/cryptlv/var; mount -t ext4 /dev/cryptlv/var /mnt/var -o relatime,nodev,nosuid,noexec
lvcreate -l 5%VG cryptlv -n var_tmp; mkfs.ext4 /dev/cryptlv/var_tmp; mount -t ext4 /dev/cryptlv/var_tmp /mnt/var/tmp -o nodev,nosuid,noexec
lvcreate -l 5%VG cryptlv -n var_log; mkfs.ext4 /dev/cryptlv/var_log; mount -t ext4 /dev/cryptlv/var_log /mnt/var/log -o relatime,nodev,nosuid,noexec
lvcreate -l 5%VG cryptlv -n var_log_audit; mkfs.ext4 /dev/cryptlv/var_log_audit; mount -t ext4 /dev/cryptlv/var_log_audit /mnt/var/log/audit -o relatime,nodev,nosuid,noexec
lvcreate -l 100%FREE cryptlv -n home; mkfs.ext4 /dev/cryptlv/home; mount -t ext4 /dev/cryptlv/home /mnt/home -o relatime,nodev,nosuid
if [[ -d "/sys/firmware/efi" ]]; then
    mount -t vfat "${PART1}" /mnt/boot -o noatime,ro
else
    mount -t ext4 "${PART1}" /mnt/boot -o noatime,ro
fi
mount -t tmpfs tmpfs /mnt/tmp -o nodev,nosuid,noexec,mode=1777
genfstab -U /mnt >> /mnt/etc/fstab

echo -e "-------------------------------------------------
                Base Install
-------------------------------------------------
"
basestrap /mnt base linux linux-firmware --noconfirm --needed
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
cp -R "${SCRIPT_DIR}" /mnt/root/easy-a
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

echo -e "-------------------------------------------------
                Stage Complete
-------------------------------------------------

Starting the next stage in 3 seconds..."
sleep 3
arch-chroot /mnt /root/easy-a/scripts/2-setup.sh