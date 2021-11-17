#!/usr/bin/env bash

clear   # Clear the TTY
set -e  # The script will not run if we CTRL + C, or in case of an error
set -u  # Treat unset variables as an error when substituting

## This are the defaults, so it's easier to test the script
# part=yes
# keymap=us
# ipv=ipv6
# username=csjarchlinux  # Can only be lowercase and no signs
# hostname=desktop
# user_password=csjarchlinux
# root_password=csjarchlinux

read -p "Enter keymap, or press enter to use defaults: " keymap
if [[ -z $keymap ]]; then
    keymap=us
fi

read -p "Enter user name, or press enter to use defaults: " username
if [[ -z $username ]]; then
    username=csjarchlinux
fi

read -p "Enter host name, or press enter to use defaults: " hostname
if [[ -z $hostname ]]; then
    hostname=csjarchlinux
fi

read -s -p "Enter user password, or press enter to use defaults: " user_password
if [[ -z $user_password ]]; then
    user_password=csjarchlinux
fi

read -s -p "Enter root password, or press enter to use defaults: " root_password
if [[ -z $root_password ]]; then
    root_password=csjarchlinux
fi

read -p "Do you want to wipe full drive yes or no, or press enter to use defaults: " part
if [[ -z $part ]]; then
    part=yes
fi

if [[ $part == "no" ]]; then
    pacman -Sy dialog --noconfirm  # Install dialog for selecting disk
    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)  # Gets disk info for selection
    drive=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1  # Chose which drive to format
    clear  # Clears blue screen from
    lsblk  # Shows avalable drives
    echo ${drive}  # Confirms drive selection
    part_boot="$(ls ${drive}* | grep -E "^${drive}p?1$")"  # Finds boot partion
    part_root="$(ls ${drive}* | grep -E "^${drive}p?2$")"  # Finds root partion
    cryptsetup luksOpen ${part_root} cryptroot  # Open the mapper
    mount /dev/mapper/cryptroot /mnt

    # Clearing non home data
    btrfs subvolume delete /mnt/@
    btrfs subvolume delete /mnt/@pkg
    btrfs subvolume delete /mnt/@var
    btrfs subvolume delete /mnt/@srv
    btrfs subvolume delete /mnt/@tmp

    # Creating new subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@srv
    btrfs subvolume create /mnt/@tmp
    umount /mnt

    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
    mkdir -p /mnt2/{home,var/cache/pacman/pkg,var,srv,tmp,boot}  # Create directories for each subvolume
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@srv /dev/mapper/cryptroot /mnt/srv
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
    chattr +C /mnt/var  # Copy on write disabled
	mount ${part_boot} /mnt/boot  # Mount the boot partition
else
	pacman -Sy dialog --noconfirm  # Install dialog for selecting disk
    devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)  # Gets disk info for selection
    drive=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1  # Chose which drive to format
    clear  # Clears blue screen from
    lsblk  # Shows available drives
    echo ${drive}  # Confirms drive selection
    sgdisk --zap-all ${drive}  # Delete tables
    printf "n\n1\n\n+333M\nef00\nn\n2\n\n\n\nw\ny\n" | gdisk ${drive}  # Format the drive

    part_boot="$(ls ${drive}* | grep -E "^${drive}p?1$")"  # Finds boot partion
    part_root="$(ls ${drive}* | grep -E "^${drive}p?2$")"  # Finds root partion

    echo ${part_boot}  # Confirms boot partion selection
    echo ${part_root}  # Confirms root partion selection

    mkdir -p -m0700 /run/cryptsetup  # Change permission to root only
    cryptsetup luksFormat --type luks2 ${part_root}
    cryptsetup luksOpen ${part_root} cryptroot  # Open the mapper

    mkfs.vfat -F32 ${part_boot}  # Format the EFI partition
    mkfs.btrfs /dev/mapper/cryptroot  # Format the encrypted partition

    mount /dev/mapper/cryptroot /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@pkg
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@srv
    btrfs subvolume create /mnt/@tmp
    umount /mnt

    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/{home,var/cache/pacman/pkg,var,srv,tmp,boot}  # Create directories for each subvolume
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@srv /dev/mapper/cryptroot /mnt/srv
    mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
    chattr +C /mnt/var  # Copy on write disabled
    mount ${part_boot} /mnt/boot  # Mount the boot partition
fi

timedatectl set-ntp true  # Synchronize motherboard clock

sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  # Making pacman prettier
sed -i "s/#Color/Color/g" /etc/pacman.conf  # Add color to pacman
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 10/g" /etc/pacman.conf  # Parallel downloads

read -p "Do you want to update and sync the mirrors before proceeding? type y for yes" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	# This lines check for ipv6 connection by pinging Google via Googles ipv6 address, if that
	# fails check to see if there's an internet connection. After the quick check it then sets
	# ipv4 or ipv6 for reflector.
	if ping -q -c 1 -W 1 2001:4860:4860::8888 >/dev/null; then
		ipv=ipv6
	else
		if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
			ipv=ipv4
		else
			echo "Not online"
		fi
	fi

	reflector --latest 25 --verbose --protocol https --sort rate --save /etc/pacman.d/mirrorlist --$ipv
	pacman -Syy
fi

# Cpu detection
lscpu | grep 'GenuineIntel' &> /dev/null
if [[ $? -eq 0 ]]; then
	cpu_model="intel"
else
	cpu_model="amd"
fi
echo -e "Your CPU is $cpu_model"

pacstrap -i /mnt base base-devel linux linux-firmware \
	networkmanager efibootmgr btrfs-progs neovim zram-generator zsh snapper apparmor \
	${cpu_model}-ucode

genfstab -U /mnt >> /mnt/etc/fstab  # Generate the entries for fstab
arch-chroot /mnt /bin/bash << EOF

timedatectl set-ntp true
ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null
hwclock --systohc
sed -i "s/#en_US/en_US/g; s/#es_AR/es_AR/g" /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
locale-gen

echo -e "127.0.0.1\tlocalhost" > /etc/hosts
echo -e "::1\t\tlocalhost" >> /etc/hosts
echo -e "127.0.1.1\t$hostname.localdomain\t$hostname" >> /etc/hosts

echo -e "KEYMAP=$keymap" > /etc/vconsole.conf
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults !tty_tickets" >> /etc/sudoers
sed -i "/#Color/a ILoveCandy" /etc/pacman.conf
sed -i "s/#Color/Color/g; s/#ParallelDownloads = 5/ParallelDownloads = 6/g; s/#UseSyslog/UseSyslog/g; s/#VerbosePkgLists/VerbosePkgLists/g" /etc/pacman.conf
sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf

echo -e "$hostname" > /etc/hostname
useradd -g users -G wheel -m $username
echo -en "$root_password\n$root_password" | passwd
echo -en "$user_password\n$user_password" | passwd $username

curl https://raw.githubusercontent.com/santigo-zero/csjarchlinux/master/20-packages.sh > /home/$username/20-packages.sh
chmod +x /home/$username/20-packages.sh
chown $username /home/$username/20-packages.sh

systemctl enable NetworkManager.service fstrim.timer snapper-timeline.timer snapper-cleanup.timer apparmor

snapper -c root create-config /
snapper -c home create-config /home
sed -i 's/ALLOW_GROUPS=""/ALLOW_GROUPS="wheel"'/g /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="16"'/g /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"'/g /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="4"'/g /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="1"'/g /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"'/g /etc/snapper/configs/root
sed -i 's/ALLOW_GROUPS=""/ALLOW_GROUPS="wheel"'/g /etc/snapper/configs/home
sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="16"'/g /etc/snapper/configs/home
sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"'/g /etc/snapper/configs/home
sed -i 's/TIMELINE_LIMIT_WEEKLY="0"/TIMELINE_LIMIT_WEEKLY="4"'/g /etc/snapper/configs/home
sed -i 's/TIMELINE_LIMIT_MONTHLY="10"/TIMELINE_LIMIT_MONTHLY="1"'/g /etc/snapper/configs/home
sed -i 's/TIMELINE_LIMIT_YEARLY="10"/TIMELINE_LIMIT_YEARLY="0"'/g /etc/snapper/configs/home

journalctl --vacuum-size=100M --vacuum-time=2weeks

touch /etc/systemd/zram-generator.conf
tee -a /etc/systemd/zram-generator.conf << END
[zram0]
zram-fraction = 1
max-zram-size = 4096
END

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

touch /etc/udev/rules.d/backlight.rules
tee -a /etc/udev/rules.d/backlight.rules << END
RUN+="/bin/chgrp video /sys/class/backlight/intel_backlight/brightness"
RUN+="/bin/chmod g+w /sys/class/backlight/intel_backlight/brightness"
END

touch /etc/udev/rules.d/81-backlight.rules
tee -a /etc/udev/rules.d/81-backlight.rules << END
SUBSYSTEM=="backlight", ACTION=="add", KERNEL=="intel_backlight", ATTR{brightness}="9000"
END

mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/100-systemd-boot.hook
tee -a /etc/pacman.d/hooks/100-systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
END

sed -i "s/^HOOKS.*/HOOKS=(base systemd keyboard autodetect sd-vconsole modconf block sd-encrypt btrfs filesystems fsck)/g" /etc/mkinitcpio.conf
sed -i 's/^MODULES.*/MODULES=(intel_agp i915)/' /etc/mkinitcpio.conf
mkinitcpio -P
bootctl --path=/boot/ install

mkdir -p /boot/loader/
tee -a /boot/loader/loader.conf << END
default arch.conf
console-mode max
editor no
END

mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title Arch Linux
linux /vmlinuz-linux
initrd /$cpu_model-ucode.img
initrd /initramfs-linux.img
options lsm=lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value ${part_root})=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-zen.conf
tee -a /boot/loader/entries/arch-zen.conf << END
title Arch Linux Zen
linux /vmlinuz-linux-zen
initrd /$cpu_model-ucode.img
initrd /initramfs-linux-zen.img
options lsm=lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value ${part_root})=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-lts.conf
tee -a /boot/loader/entries/arch-lts.conf << END
title Arch Linux LTS
linux /vmlinuz-linux-lts
initrd /$cpu_model-ucode.img
initrd /initramfs-linux-lts.img
options lsm=lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value ${part_root})=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard nmi_watchdog=0 quiet rw
END

EOF
