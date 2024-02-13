#!/usr/bin/env bash

###################
## Global Variables
CPU="$(lscpu | awk '/Vendor ID:/ {print $3}')" # Getting CPU manufacturer
CORES="$(grep -c ^processor /proc/cpuinfo)" # Getting CPU core count
GPU="$(lspci | awk '/VGA/ {print $1=$2=$3=$4=""; print $0}')" # Getting GPU manufacturer
ISO="$(curl -4 ifconfig.co/country-iso)" # Getting approximate location
KEYMAP="us"
TIMEZONE="America/Belize"

###############
## Disk Control
ssd () {
read -rp "Is this an SSD? (y/n): " ssd
case $ssd in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed."; SSD=1; MOUNTOPTS="noatime,compress=zstd,ssd,commit=120";;
    n|N|no|NO|No|nO) echo -e "\nConfirmed."; SSD=0; MOUNTOPTS="noatime,compress=zstd,commit=120";;
    *) echo -e "\nI'm sorry, I don't understand.\n"; ssd;;
esac
}

verify_disk_again () {
echo -e "\nAre you sure this is OK? WARNING! THIS WILL DELETE ALL DATA ON THE DISK!"
read -rp "Answer (y/n): " disk_verified
case $disk_verified in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; DISK="/dev/${disk}"; ssd;;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another disk.\n"; select_disk;;
    *) echo -e "\nI'm sorry, I don't understand."; verify_disk_again;;
esac
}

verify_disk () {
echo -e "\nYou have chosen to use disk: $disk"
read -rp "Is this OK? (y/n): " confirm_disk
case $confirm_disk in
    y|Y|yes|YES|Yes|yES) verify_disk_again;;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another disk.\n"; select_disk;;
    *) echo -e "\nI'm sorry, I don't understand."; verify_disk;;
esac
}

validate_disk () {
readarray -t avail_disks < <(lsblk -n --output TYPE,KNAME | awk '$1=="disk"{print $2}')
declare -i disk_valid=0
for disks in "${avail_disks[@]}"; do
    [[ "$disk" = "$disks" ]] && declare -ir disk_valid=1
done
if [[ "$disk_valid" -eq 1 ]]; then
    verify_disk
else
    echo -e "\nThe selected disk does not exist. Please select an available disk.\n"
    select_disk
fi
}

select_disk () {
echo -e "Disks available on system:\n"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print $2" - "$3}'
echo -e "\nPlease enter the disk you would like to use."
read -rp "Choice: " disk
validate_disk
}

##################
## Service Control
service_ctl() {
declare ServChk=$1
if [[ $(systemctl list-units --all -t service --full --no-legend "${ServChk}.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "${ServChk}.service" ]]; then
    echo "${ServChk} service is already enabled, enjoy..."
else
    echo "${ServChk} service is not running, enabling..."
    sudo systemctl enable --now ${ServChk}.service
    echo "${ServChk} service enabled, and running..."
fi
}

##################
## Package Control
pkg_installed() {
declare PkgIn=$1
if pacman -Qi ${PkgIn} &> /dev/null; then
    #echo "${PkgIn} is already installed..."
    return 0
else
    #echo "${PkgIn} is not installed..."
    return 1
fi
}

pkg_available() {
declare PkgIn=$1
if pacman -Si ${PkgIn} &> /dev/null; then
    #echo "${PkgIn} available in arch repo..."
    return 0
else
    #echo "${PkgIn} not available in arch repo..."
    return 1
fi
}

aur_available() {
declare PkgIn=$1
if yay -Si ${PkgIn} &> /dev/null; then
    #echo "${PkgIn} available in aur repo..."
    return 0
else
    #echo "aur helper is not installed..."
    return 1
fi
}