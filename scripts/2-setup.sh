#!/usr/bin/env bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
functions="${SCRIPT_DIR}/helpers/functions.sh"
packages="${SCRIPT_DIR}/helpers/packages.lst"

source "${functions}"

echo -e "-------------------------------------------------
                Second Stage: Setup
-------------------------------------------------

Starting..."
timedatectl set-ntp true

echo -e "-------------------------------------------------
                Host & User Details
-------------------------------------------------

Please name your host."
read -rp "Hostname: " machine
echo "${machine,,}" > /etc/hostname
echo -e "Please enter a strong password for root." && passwd
echo -e "\nPlease choose a username."
read -rp "Username: " username
useradd -m -G wheel -s /bin/bash "${username,,}"
echo -e "Please enter a strong password for ${username,,}." && passwd "${username,,}"

sed -i -e "/ParallelDownloads/,/Color/"'s/^#//' /etc/pacman.conf
case "${CPU}" in
	GenuineIntel) echo "intel-ucode" >> "${PACKAGES}"; proc_ucode="intel-ucode.img" ;;
	#GenuineIntel) pacman -S --noconfirm intel-ucode; proc_ucode="intel-ucode.img" ;;
    AuthenticAMD) echo "amd-ucode" >> "${PACKAGES}"; proc_ucode="amd-ucode.img" ;;
esac
if grep -E "NVIDIA|GeForce" <<< "${GPU}"; then
    echo "nvidia" >> "${PACKAGES}"
    nvidia-xconfig
elif grep -E "Radeon|AMD" <<< "${GPU}"; then
    echo "xf86-video-amdgpu" >> "${PACKAGES}"
elif grep -E "Integrated Graphics Controller|Intel Corporation UHD" <<< "${GPU}"; then
    echo -e "libva-intel-driver\nlibvdpau-va-gl\nlib32-vulkan-intel\nvulkan-intel\nlibva-intel-driver\nlibva-utils\nlib32-mesa" >> "${PACKAGES}"
fi
yay -Sy --noconfirm --needed "${packages[@]}"


install_list="${packages}"
ofs=$IFS
IFS='|'
while read -r pkg deps; do
    pkg="${pkg// /}"
    if [[ -z "${pkg}" ]]; then
        continue
    fi
    if [[ ! -z "${deps}" ]]; then
        while read -r cdep; do
            pass=$(cut -d '#' -f 1 ${install_list} | awk -F '|' -v chk="${cdep}" '{if($1 == chk) {print 1;exit}}')
            if [[ -z "${pass}" ]]; then
                if pkg_installed ${cdep}; then
                    pass=1
                else
                    break
                fi
            fi
        done < <(echo "${deps}" | xargs -n1)
        if [[ ${pass} -ne 1 ]]; then
            echo "skipping ${pkg} due to missing (${deps}) dependency..."
            continue
        fi
    fi
    if pkg_installed ${pkg}; then
        echo "skipping ${pkg}..."
    elif pkg_available ${pkg}; then
        echo "queueing ${pkg} from arch repo..."
        pkg_arch=`echo $pkg_arch ${pkg}`
    elif aur_available ${pkg}; then
        echo "queueing ${pkg} from aur..."
        pkg_aur=`echo $pkg_aur ${pkg}`
    else
        echo "error: unknown package ${pkg}..."
    fi
done < <( cut -d '#' -f 1 $install_list )
IFS=${ofs}

if [[ $(echo $pkg_arch | wc -w) -gt 0 ]]; then
    echo "installing $pkg_arch from arch repo..."
    sudo pacman ${use_default} -S $pkg_arch
fi
if [[ $(echo $pkg_aur | wc -w) -gt 0 ]]; then
    echo "installing $pkg_aur from aur..."
    yay ${use_default} -S $pkg_aur
fi


mkinitcpio -p linux

echo "cryptdevice=UUID=$(blkid -s UUID -o value "${PART2}"):/dev/mapper/cryptroot root=/dev/cryptlv/root:allow-discards,no_read_workqueue,no_write_workqueue" >> /etc/default/grub
if [[ -d "/sys/firmware/efi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
else
    grub-install --recheck "${DISK}"
fi
grub-mkconfig -o /boot/grub/grub.cfg

sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j${CORES}\"/g" -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $CORES -z -)/g" /etc/makepkg.conf
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
timedatectl --no-ask-password set-timezone "${TIMEZONE}" && timedatectl --no-ask-password set-ntp 1
localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8" && localectl --no-ask-password set-keymap "${KEYMAP}"

echo -e "-------------------------------------------------
                    Start Services
-------------------------------------------------"

systemctl enable lightdm.service
ntpd -qg
systemctl enable ntpd.service
systemctl enable NetworkManager.service
systemctl disable --now dhcpcd.service

echo -e "-------------------------------------------------
                    Clean Up
-------------------------------------------------"
# Removing no password sudo rights
sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
# Adding sudo rights
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
rm -rf /root/easy-a /home/"${username}"/easy-a

echo -e "-------------------------------------------------
                Install Complete
-------------------------------------------------

Please eject the install media and reboot."