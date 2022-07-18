#!/bin/bash
# This script will get the user's preferences 
# such as disk, partition scheme, timezone, keyboard layout,
# username, password, etc.

# Variables
CPU=$(lscpu | awk '/Vendor ID:/ {print $3}') # Getting CPU manufacturer
CORES=$(grep -c ^processor /proc/cpuinfo) # Getting CPU core count
#ISO=$(curl -4 ifconfig.co/country-iso) # Getting approximate location

# Set options in setup.conf
set_option () {
if grep -Eq "${1}" $CONFIG_FILE; then sed -i -e "s/${1}=.*/${1}=${2}/g" $CONFIG_FILE; else echo "${1}=${2}" >> $CONFIG_FILE; fi
}

system () {
echo -ne "
The following system details have been detected:

CPU: ${CPU}
CPU Cores: ${CORES}
Location: ${ISO}
Script Directory: ${SCRIPT_DIR}
"
set_option CPU $CPU
set_option CORES $CORES
set_option GPU $GPU
set_option ISO $ISO
set_option SCRIPT_DIR $SCRIPT_DIR
}

#userpass () {
#echo -e "\n\nPlease enter a strong user password."
#read -rsp "Password: " password
#echo -e "\n\nPlease re-enter your password."
#read -rsp "Password: " password_confirm
#if [[ "$password_confirm" == "$password" ]]; then
#    set_option PASSWORD $password
#else
#    echo -ne "\n\nPasswords do not match! Please try again.\n"; userpass
#fi
#}

user () {
echo -ne "
-------------------------------------------------
                Host/User Details
-------------------------------------------------
"
echo -e "\nPlease name your host."
read -p "Hostname: " hostname
set_option HOSTNAME ${hostname,,} # Convert to lower case
echo -e "\nPlease choose a username."
read -p "Username: " username
set_option USERNAME ${username,,}
echo -e "NOTE: You will be prompted to create a user password in the final setup stage. This is to ensure that your password is not stored unsafely during install."
#userpass
}

#luks_pass () {
#echo -e "\n\nPlease enter a strong password for drive encryption."
#read -rsp "Password: " luks_pass # Read password without echo
#echo -e "\n\nPlease re-enter your password."
#read -rsp "Password: " luks_confirm
#if [[ "$luks_confirm" == "$luks_pass" ]]; then
#    set_option LUKS_PASS $luks_pass
#else
#    echo -e "\n\nPasswords do not match! Please try again."; luks_pass
#fi
#}


###############
# Partition Management

define_lvm () {
echo -e "Please define some parameters to create your LVM."
echo -e "\nPlease name your volume group."
read -p "Name: " vol_group
echo -e "\nHow many logical volumes will you need?"
read -p "# of LVs: " vol_number
echo -e "\nPlease name your LVs according to that of system directories (i.e. home, tmp, var, etc), as a directory will be created for every named LV. The size must be entered in the format: 512M, 1G, 10G, etc. To use the remainder of the disk for the last LV, enter the size exactly as such: '100%FREE'."
echo -e 
lv_name=()
lv_size=()
for (( i=0; i<$vol_number; i++ ))
do
    read -p "Name of LV: " name
    [[ $name ]] || break
    lv_name+=("$name")
    read -p "Size of $name: " size
    [[ $size ]] || break
    lv_size+=("$size")
done
echo "lv_name=(${lv_name[*]})" >> $CONFIG_FILE
echo "lv_size=(${lv_size[*]})" >> $CONFIG_FILE
}

part_confirm () {
read -p "Are you sure this scheme is OK? (y/n): " confirm_part
case $confirm_part in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option PS $part_choice; if [[ "$part_choice" == "encryptedlvm" ]]; then define_lvm; fi;;
    n|N|no|NO|No|nO) echo -e "\nWell then, please select another partition scheme."; part_scheme;;
    *) echo -e "\nI'm sorry, I don't understand.\n"; part_confirm;;
esac
}

part_basic () {
echo -e "\nThe basic partition scheme creates the standard boot (/boot) and root (/) partitions."
part_choice="basic"
part_confirm
}

part_crypt () {
echo -e "\nThe encrypted partition scheme creates a standard boot (/boot) partition and a luks-encrypted root (/) partition."
echo -e "NOTE: You will be prompted to create an encryption key in the pre-setup stage. This is to ensure that your password is not stored unsafely during install."
part_choice="encrypted"
part_confirm
}

part_crypt_lvm () {
echo -e "\nThe encrypted LVM partition scheme creates a standard boot (/boot) partition and a luks-encrypted root (/) partition with an LVM on top of it."
echo -e "NOTE: You will be prompted to create an encryption key in the pre-setup stage. This is to ensure that your password is not stored unsafely during install."
part_choice="encryptedlvm"
part_confirm
}

# This function will handle partition scheming. At the moment, only ext4 is supported.
# Others may be added in the future.
part_scheme () {
echo -ne "
-------------------------------------------------
            Partition Scheme Selection
-------------------------------------------------
"
echo -e "Please select a partition scheme:

1)  Basic
2)  Encrypted
3)  Encrypted LVM
0)  Exit
"
read -p "Choice: " PS
case $PS in
    1) part_basic;;
    2) part_crypt;; #luks_pass;;
    3) part_crypt_lvm;; #luks_pass;;
    0) exit;;
    *) echo -e "\nI'm sorry, I don't understand."; part_scheme;;
esac
}


###########################
## Disk Management

ssd () {
read -p "Is this an SSD? (y/n): " ssd
case $ssd in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed."; set_option SSD 1; set_option MOUNTOPTS "noatime,compress=zstd,ssd,commit=120";;
    n|N|no|NO|No|nO) echo -e "\nConfirmed."; set_option SSD 0; set_option MOUNTOPTS "noatime,compress=zstd,commit=120";;
    *) echo -e "\nI'm sorry, I don't understand.\n"; ssd;;
esac
}

verify_disk_again () {
echo -e "\nAre you sure this is OK?"
echo -e "WARNING! THIS WILL DELETE ALL DATA ON THE DISK!"
read -p "Answer (y/n): " disk_verified
case $disk_verified in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option DISK "/dev/$disk"; ssd;;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another disk.\n"; select_disk;;
    *) echo -e "\nI'm sorry, I don't understand."; verify_disk_again;;
esac
}

verify_disk () {
echo -e "\nYou have chosen to use disk: " $disk
read -p "Is this OK? (y/n): " confirm_disk
case $confirm_disk in
    y|Y|yes|YES|Yes|yES) verify_disk_again;;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another disk.\n"; select_disk;;
    *) echo -e "\nI'm sorry, I don't understand."; verify_disk;;
esac
}

validate_disk () {
readarray -t disk_array < <(lsblk -n --output TYPE,KNAME | awk '$1=="disk"{print $2}')
if [[ "${disk_array[@]}" =~ "${disk}" ]]; then verify_disk; else echo -e "\nThe selected disk does not exist. Please select an available disk.\n"; select_disk; fi
}

select_disk () {
echo -e "Disks available on system:\n"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print $2" - "$3}'
echo -ne "
Please enter the disk you would like to use.
"
read -p "Choice: " disk
validate_disk
}

disk () {
echo -ne "
-------------------------------------------------
                Disk Preparation
-------------------------------------------------
"
select_disk
}

##############
# Timezone Management

verify_timezone () {
read -p "Is this correct? (y/n): " confirm_timezone
case $confirm_timezone in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed.\n"; set_option TIMEZONE $timezone;;
    n|N|no|NO|No|nO) echo -e "\nWell, please enter your desired timezone (e.g. Europe/London)."; read -p "Timezone: " timezone_new; set_option TIMEZONE $timezone_new;;
    *) echo -e "\nI'm sorry, I don't understand.\n"; verify_timezone;;
esac
}

timezone () {
echo -ne "
-------------------------------------------------
                Timezone Selection
-------------------------------------------------
"
# Added this from arch wiki https://wiki.archlinux.org/title/System_time
timezone="$(curl --fail ipapi.co/timezone)"
echo -e "\nDetected your timezone to be: " $timezone
verify_timezone
}

##################
# Keyboard Layout Management

verify_keymap () {
echo -e "\nYour chosen keyboard layout is: $keymap"
read -p "Is this OK? (y/n): " confirm_keymap
case $confirm_keymap in
    y|Y|yes|YES|Yes|yES) echo -e "\nConfirmed."; set_option KEYMAP $keymap;;
    n|N|no|NO|No|nO) echo -e "\nWell, please select another layout."; keymap;;
    *) echo -e "\nI'm sorry, I don't understand."; verify_keymap;;
esac
}

keymap () {
echo -ne "
-------------------------------------------------
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
read -p "Choice: " keymap
verify_keymap
}

#########
# START

system
user
disk
part_scheme
timezone
keymap
echo -ne "-------------------------------------------------
                Pre-setup Complete
-------------------------------------------------

Starting stage 1 in 3 seconds."
sleep 3
bash $SCRIPT_DIR/stages/1-presetup.sh
