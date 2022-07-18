#!/usr/bin/env bash

# Set options in setup.conf
set_option () { if grep -Eq "${1}" "$CONFIG_FILE"; then sed -i -e "s/${1}=.*/${1}=${2}/g" "$CONFIG_FILE"; else echo "${1}=${2}" >> "$CONFIG_FILE"; fi; }

start_stages () { bash "$SCRIPT_DIR"/stages/1-presetup.sh; }

start () {
echo -e "Are you ready to start?"
read -rp "Choice (y/n): " begin
case $begin in
    y|Y|yes|YES|Yes|yES) echo -e "\nGreat! Starting in 3 seconds.\n"; sleep 3; start_stages;;
    n|N|no|NO|No|nO) echo -e "\nWell then, goodbye! :)\n"; exit;;
    *) echo -e "\nI'm sorry. I don't understand.\n"; choice;;
esac
}

welcome () {
clear
echo -e "-------------------------------------------------
                Welcome To...
-------------------------------------------------
███████╗ █████╗ ███████╗██╗   ██╗       █████╗  
██╔════╝██╔══██╗██╔════╝██║   ██║      ██╔══██╗ 
█████╗  ███████║███████╗╚██████╔╝█████╗███████║ 
██╔══╝  ██╔══██║╚════██║ ╚═██╔═╝ ╚════╝██╔══██║ 
███████╗██║  ██║███████║   ██║         ██║  ██║ 
╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝         ╚═╝  ╚═╝ 
-------------------------------------------------
          An Easy Artix Installer
-------------------------------------------------
"
}

stage_complete () {
echo -e "-------------------------------------------------
                Stage Complete
-------------------------------------------------

Starting the next stage in 3 seconds..."
sleep 3
}

system () {
CPU="$(lscpu | awk '/Vendor ID:/ {print $3}')" && declare -r CPU # Getting CPU manufacturer
set_option CPU "$CPU"
CORES="$(grep -c ^processor /proc/cpuinfo)" && declare -r CORES # Getting CPU core count
set_option CORES "$CORES"
GPU="$(lspci | awk '/VGA/ {print $1=$2=$3=$4=""; print $0}')" && declare -r GPU # Getting GPU manufacturer
set_option GPU "$GPU"
ISO="$(curl -4 ifconfig.co/country-iso)" && declare -rx ISO # Getting approximate location
set_option ISO "$ISO"
}

user () {
echo -e "-------------------------------------------------
                Host & User Details
-------------------------------------------------
Please name your host."
read -rp "Hostname: " machine
echo -e "\nPlease choose a username."
read -rp "Username: " username
echo -e "NOTE: You will be prompted to create a user password in the user setup stage. This is to ensure that your password is not stored insecurely."
set_option MACHINE "${machine,,}" # Convert to lower case
set_option USERNAME "${username,,}"
}

###############
# Partition Management
part_confirm () {
read -rp "Are you sure this scheme is OK? (y/n): " confirm_part
case $confirm_part in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option PS "$part_choice";;
    n|N|no|NO|No|nO) echo -e "\nWell then, please select another partition scheme."; part_scheme;;
    *) echo -e "\nI'm sorry, I don't understand.\n"; part_confirm;;
esac
}

part_basic () {
echo -e "\nThe basic partition scheme creates the standard root (/) and boot (/boot) partitions."
declare -r part_choice="basic"
part_confirm
}

part_crypt () {
echo -e "\nThe encrypted partition scheme creates a standard boot (/boot) partition and a luks-encrypted root (/) partition."
echo -e "NOTE: You will be prompted to create an encryption key in the pre-setup stage. This is to ensure that your password is not stored unsafely during install."
declare -r part_choice="encrypted"
part_confirm
}

part_crypt_lvm () {
echo -e "\nThe encrypted LVM partition scheme creates a standard boot (/boot) partition and a luks-encrypted root (/) partition with an LVM on top of it."
echo -e "NOTE: You will be prompted to create an encryption key in the pre-setup stage. This is to ensure that your password is not stored unsafely during install."
declare -r part_choice="encryptedlvm"
part_confirm
}

part_scheme () {
echo -e "-------------------------------------------------
            Partition Scheme Selection
-------------------------------------------------
Please select a partition scheme:

1)  Basic
2)  Encrypted
3)  Encrypted LVM
0)  Exit
"
read -rp "Choice: " PS
case $PS in
    1) part_basic;;
    2) part_crypt;;
    3) part_crypt_lvm;;
    0) exit;;
    *) echo -e "\nI'm sorry, I don't understand."; part_scheme;;
esac
}

###########################
## Disk Management
ssd () {
read -rp "Is this an SSD? (y/n): " ssd
case $ssd in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed."; set_option SSD 1; set_option MOUNTOPTS "noatime,compress=zstd,ssd,commit=120";;
    n|N|no|NO|No|nO) echo -e "\nConfirmed."; set_option SSD 0; set_option MOUNTOPTS "noatime,compress=zstd,commit=120";;
    *) echo -e "\nI'm sorry, I don't understand.\n"; ssd;;
esac
}

verify_disk_again () {
echo -e "\nAre you sure this is OK?
WARNING! THIS WILL DELETE ALL DATA ON THE DISK!"
read -rp "Answer (y/n): " disk_verified
case $disk_verified in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option DISK "/dev/$disk"; ssd;;
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
for disks in "${avail_disks[@]}"
do
    [[ "$disk" = "$disks" ]] && declare -ir disk_valid=1
done
if [[ "$disk_valid" -eq 1 ]]; then verify_disk; else echo -e "\nThe selected disk does not exist. Please select an available disk.\n"; select_disk; fi
}

select_disk () {
echo -e "Disks available on system:\n"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print $2" - "$3}'
echo -e "\nPlease enter the disk you would like to use."
read -rp "Choice: " disk
validate_disk
}

disk () {
echo -e "-------------------------------------------------
                Disk Preparation
-------------------------------------------------"
select_disk
}

#######################
# Timezone Management
verify_timezone () {
read -rp "Is this correct? (y/n): " confirm_timezone
case $confirm_timezone in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option TIMEZONE "$timezone";;
    n|N|no|NO|No|nO) echo -e "\nWell, please enter your desired timezone (e.g. Europe/London)."; read -rp "Timezone: " timezone_new; set_option TIMEZONE "$timezone_new";;
    *) echo -e "\nI'm sorry, I don't understand.\n"; verify_timezone;;
esac
}

timezone () {
echo -e "-------------------------------------------------
                Timezone Selection
-------------------------------------------------"
timezone="$(curl --fail ipapi.co/timezone)" # Added this from arch wiki https://wiki.archlinux.org/title/System_time
echo -e "Detected your timezone to be: $timezone"
verify_timezone
}

##############################
# Keyboard Layout Management
verify_keymap () {
read -rp "Is this OK? (y/n): " confirm_keymap
case $confirm_keymap in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed."; set_option KEYMAP "$keymap";;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another layout."; keymap;;
    *) echo -e "\nI'm sorry, I don't understand.\n"; verify_keymap;;
esac
}

keymap () {
echo -e "-------------------------------------------------
            Keyboard Layout Selection
-------------------------------------------------
Please select your preferred keyboard layout from
this list:

    -by             -ca             -cf
    -cz             -de             -dk
    -es             -et             -fa
    -fi             -fr             -gr
    -hu             -il             -it
    -lt             -lv             -mk
    -nl             -no             -pl
    -ro             -ru             -sg
    -ua             -uk             -us
"
read -rp "Choice: " keymap
echo -e "\nYour chosen keyboard layout is: $keymap"
verify_keymap
}

mount_boot () {
mkdir /mnt/boot
if [[ -d "/sys/firmware/efi" ]]; then mount -t vfat "$PART1" /mnt/boot -o noatime,ro; else mount -t ext4 "$PART1" /mnt/boot -o noatime,ro; fi
}

create_luks_container () {
cryptsetup --type luks2 --cipher aes-xts-plain64 --hash sha512 --iter-time 10000 --key-size 512 --pbkdf argon2id --use-urandom -y -v luksFormat "$PART2"
cryptsetup open "$PART2" cryptroot # Opening container
}

################
# Script Start
#system
#user
#disk
#part_scheme
#timezone
#keymap

