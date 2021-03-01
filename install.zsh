#!/usr/bin/env zsh

echo "Hello! Running marek's archlinux install script..."
timedatectl set-ntp true



echo "\n[1] Partitioning drives...\n"

lsblk -i -o NAME,RM,RO,SIZE,TYPE,MOUNTPOINT,FSTYPE
echo ""

default_disk=$(lsblk -r -o NAME,TYPE,RO,RM,MOUNTPOINT | awk 'NR != 1 && $2=="disk" && $3==0 && $4==0 && $5=="" { print $1 }' | head -n 1)

vared -p "Please input drive to install arch on (default $default_disk): " -c disk

if [ -z $disk ]; then disk=$default_disk fi
disk="/dev/$disk"

echo "Partitioning $disk"

sfdisk --dump $disk > partitions-backup

cat << EOF | sfdisk --label gpt -w always $disk
, 512M, U, *
, , L, -
quit
EOF

boot_part="$disk"1
root_part="$disk"2



echo "\n[2] Formatting partitions...\n"

vared -p "Please input password used for root encryption: " -c root_password


mkfs.fat -n boot -F32 $boot_part

echo $root_password | cryptsetup -q luksFormat --type luks2 --label=encroot $root_part
echo $root_password | cryptsetup open /dev/sda2 cryptroot
mkfs.ext4 /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
mkdir /mnt/boot
mount $boot_part /mnt/boot



echo "\n[3] Installing packages...\n"

pacman -Syy
pacman -S --noconfirm reflector

echo "Setting mirrorlist using reflector"
reflector --latest 40 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap /mnt base linux linux-firmware sudo

cp /mnt/etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist
arch-chroot /mnt pacman -Syy

# used packages
cat << EOF | xargs arch-chroot /mnt pacman -S --noconfirm --needed
$(pacman -Sgq base-devel)
git
sway
swaybg
swayidle
swaylock
ttf-inconsolata
bemenu
alacritty
xorg-server-xwayland
xdg-user-dirs
wl-clipboard
qt5-wayland

networkmanager

bluez

zsh
EOF



echo "\n[5] Configuring system...\n"

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# timezone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
arch-chroot /mnt hwclock --systohc
arch-chroot /mnt timedatectl set-ntp true

# locale
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
echo "pl_PL.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=pl_PL.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

# hostname
vared -p "Please input hostname: " -c device_hostname
echo $device_hostname > /mnt/etc/hostname
cat << EOF > /mnt/etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       $device_hostname.localdomain  $device_hostname
EOF

# mkinitcpio
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev keyboard autodetect keymap consolefont modconf block encrypt filesystems fsck)/g' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# enable services
arch-chroot /mnt systemctl enable NetworkManager


echo "\n[6] User configuration...\n"

vared -p "Please enter password for root: " -c root_passwd
vared -p "Please enter your username: " -c user_name
vared -p "Please enter password for $user_name: " -c user_passwd

arch-chroot /mnt useradd -G video,wheel,lp,audio -s /bin/zsh -m $user_name

echo "root:$root_passwd" | arch-chroot /mnt chpasswd
echo "$user_name:$user_passwd" | arch-chroot /mnt chpasswd

sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /mnt/etc/sudoers

mkdir -p /mnt/etc/systemd/system/getty@tty1.service.d
cat << EOF > /mnt/etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $user_name --noclear %I \$TERM
EOF

echo "exec sway" >> /mnt/home/$user_name/.zprofile



echo "\n[7] Bootloader setup...\n"

bootctl --path=/mnt/boot install
echo "default arch" > /mnt/boot/loader/loader.conf

cat << EOF > /mnt/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=LABEL=encroot:cryptroot:allow-discards root=/dev/mapper/cryptroot quiet
EOF



echo "\n[8] Finishing up...\n"
# TODO autodetect
echo "Remember to install amd-ucode or intel-ucode packages depending on your cpu"

umount $boot_part /dev/mapper/cryptroot
cryptsetup close cryptroot

echo "[☺] Done. Reboot to enjoy your new arch system"
