#!/usr/bin/env bash
set -e #break on error
set -vx #echo on
THIS="$( cd "$(dirname "$0")" ; pwd -P )"/$(basename $0)

: ${ROOT_FS_TYPE:=f2fs}
: ${MAKE_SWAP_PARTITION:=false}
: ${SWAP_SIZE_IS_RAM_SIZE:=false}
: ${SWAP_SIZE:=100MiB}
: ${TARGET:=bootable_arch.img}
: ${IMG_SIZE:=2GiB}
: ${TIME_ZONE:=Europe/Copenhagen}
: ${LANGUAGE:=en_US}
: ${TEXT_ENCODING:=UTF-8}
: ${ROOT_PASSWORD:=toor}
: ${MAKE_ADMIN_USER:=true}
: ${ADMIN_USER_NAME:=l3iggs}
: ${ADMIN_USER_PASSWORD:=sggi3l}
: ${THIS_HOSTNAME:=bootdisk}
: ${PACKAGE_LIST:=""}
: ${AUR_PACKAGE_LIST:=""}
: ${DD_TO_DISK:=false}
: ${CLEAN_UP:=false}
: ${ENABLE_AUR:=true}
: ${TARGET_IS_REMOVABLE:=false}

if [ -b $TARGET ] ; then
  TARGET_DEV=$TARGET
  for n in ${TARGET_DEV}* ; do sudo umount $n || true; done
else
  IMG_NAME=$TARGET
  rm -f "${IMG_NAME}"
  fallocate -l $IMG_SIZE "${IMG_NAME}"
  TARGET_DEV=$(sudo losetup --find)
  sudo losetup -P ${TARGET_DEV} "${IMG_NAME}"
  PEE=p
fi

sudo wipefs -a -f "${TARGET_DEV}"

NEXT_PARTITION=1
sudo sgdisk -n 0:+0:+1MiB -t 0:ef02 -c 0:biosGrub "${TARGET_DEV}" && ((NEXT_PARTITION++))
sudo sgdisk -n 0:+0:+512MiB -t 0:ef00 -c 0:boot "${TARGET_DEV}"; BOOT_PARTITION=$NEXT_PARTITION; ((NEXT_PARTITION++))
if [ "$MAKE_SWAP_PARTITION" = true ] ; then
  if [ "$SWAP_SIZE_IS_RAM_SIZE" = true ] ; then
    SWAP_SIZE=`free -b | grep Mem: | awk '{print $2}' | numfmt --to-unit=K`KiB
  fi
  sudo sgdisk -n 0:+0:+${SWAP_SIZE} -t 0:8200 -c 0:swap "${TARGET_DEV}"; SWAP_PARTITION=$NEXT_PARTITION; ((NEXT_PARTITION++))
fi
#sudo sgdisk -N 0 -t 0:8300 -c 0:${ROOT_FS_TYPE}Root "${TARGET_DEV}"; ROOT_PARTITION=$NEXT_PARTITION; ((NEXT_PARTITION++))
sudo sgdisk -N ${NEXT_PARTITION} -t ${NEXT_PARTITION}:8300 -c ${NEXT_PARTITION}:${ROOT_FS_TYPE}Root "${TARGET_DEV}"; ROOT_PARTITION=$NEXT_PARTITION; ((NEXT_PARTITION++))


sudo wipefs -a -f ${TARGET_DEV}${PEE}${BOOT_PARTITION}
sudo mkfs.fat -F32 -n BOOT ${TARGET_DEV}${PEE}${BOOT_PARTITION}
if [ "$MAKE_SWAP_PARTITION" = true ] ; then
  sudo wipefs -a -f ${TARGET_DEV}${PEE}${SWAP_PARTITION}
  sudo mkswap -L swap ${TARGET_DEV}${PEE}${SWAP_PARTITION}
fi
sudo wipefs -a -f ${TARGET_DEV}${PEE}${ROOT_PARTITION}
ELL=L
[ "$ROOT_FS_TYPE" = "f2fs" ] && ELL=l
sudo mkfs.${ROOT_FS_TYPE} -${ELL} ${ROOT_FS_TYPE}Root ${TARGET_DEV}${PEE}${ROOT_PARTITION}
sudo sgdisk -p "${TARGET_DEV}"
TMP_ROOT=/tmp/diskRootTarget
mkdir -p ${TMP_ROOT}
sudo mount -t${ROOT_FS_TYPE} ${TARGET_DEV}${PEE}${ROOT_PARTITION} ${TMP_ROOT}
sudo mkdir ${TMP_ROOT}/boot
sudo mount ${TARGET_DEV}${PEE}${BOOT_PARTITION} ${TMP_ROOT}/boot
sudo pacstrap ${TMP_ROOT} base grub efibootmgr btrfs-progs dosfstools exfat-utils f2fs-tools gpart parted jfsutils mtools nilfs-utils ntfs-3g hfsprogs ${PACKAGE_LIST}
sudo sh -c "genfstab -U ${TMP_ROOT} >> ${TMP_ROOT}/etc/fstab"
sudo sed -i '/swap/d' ${TMP_ROOT}/etc/fstab
if [ "$MAKE_SWAP_PARTITION" = true ] ; then
  SWAP_UUID=$(lsblk -n -b -o UUID ${TARGET_DEV}${PEE}${SWAP_PARTITION})
  sudo sed -i '$a #swap' ${TMP_ROOT}/etc/fstab
  sudo sed -i '$a UUID='${SWAP_UUID}'	none      	swap      	defaults  	0 0' ${TMP_ROOT}/etc/fstab
fi

cat > /tmp/chroot.sh <<EOF
#!/usr/bin/env bash
set -e #break on error
#set -vx #echo on
set -x

echo ${THIS_HOSTNAME} > /etc/hostname
ln -sf /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime
echo "${LANGUAGE}.${TEXT_ENCODING} ${TEXT_ENCODING}" >> /etc/locale.gen
locale-gen
echo LANG="${LANGUAGE}.${TEXT_ENCODING}" > /etc/locale.conf
echo "root:${ROOT_PASSWORD}"|chpasswd
if [ "$MAKE_ADMIN_USER" = true ] ; then
  useradd -m -G wheel -s /bin/bash ${ADMIN_USER_NAME}
  echo "${ADMIN_USER_NAME}:${ADMIN_USER_PASSWORD}"|chpasswd
  pacman -S --needed --noconfirm sudo
  sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/## %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers
  sed -i 's/# %wheel ALL=(ALL)/%wheel ALL=(ALL)/g' /etc/sudoers
fi
if [ "$ENABLE_AUR" = true ] ; then
  echo "[archlinuxfr]" >> /etc/pacman.conf
  echo "SigLevel = Never" >> /etc/pacman.conf
  echo 'Server = http://repo.archlinux.fr/\$arch' >> /etc/pacman.conf
  pacman -Sy --needed --noconfirm yaourt
  sed -i '$ d' /etc/pacman.conf
  sed -i '$ d' /etc/pacman.conf
  sed -i '$ d' /etc/pacman.conf
  pacman -Sy
fi
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet/GRUB_CMDLINE_LINUX_DEFAULT="rootwait/g' /etc/default/grub
INSTALLED_PACKAGES=\$(pacman -Qe)
if [[ \$INSTALLED_PACKAGES == *"openssh"* ]] ; then
  systemctl enable sshd.service
fi
if [[ \$INSTALLED_PACKAGES == *"networkmanager"* ]] ; then
  systemctl enable NetworkManager.service
fi
if [[ \$INSTALLED_PACKAGES == *"bcache-tools"* ]] ; then
  sed -i 's/MODULES="/MODULES="bcache /g' /etc/mkinitcpio.conf
  sed -i 's/HOOKS="base udev autodetect modconf block/HOOKS="base udev autodetect modconf block bcache/g' /etc/mkinitcpio.conf
fi
mkinitcpio -p linux
grub-mkconfig -o /boot/grub/grub.cfg
if [ "$ROOT_FS_TYPE" = "f2fs" ] ; then
  cat > /usr/sbin/fix-f2fs-grub.sh <<END
#!/usr/bin/env bash
ROOT_DEVICE=\\\$(df | grep -w / | awk {'print \\\$1'})
ROOT_UUID=\\\$(blkid -s UUID -o value \\\${ROOT_DEVICE})
sed -i 's,root=/[^ ]* ,root=UUID='\\\${ROOT_UUID}' ,g' \\\$1
END
  chmod +x /usr/sbin/fix-f2fs-grub.sh
  fix-f2fs-grub.sh /boot/grub/grub.cfg
fi
mkdir -p /boot/EFI/BOOT
grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "/boot/EFI/BOOT/BOOTX64.EFI" /boot/grub/grub.cfg=/boot/grub/grub.cfg  -v
cat > /etc/systemd/system/fix-efi.service <<END
[Unit]
Description=Re-Installs Grub-efi bootloader
ConditionPathExists=/usr/sbin/fix-efi.sh

[Service]
Type=forking
ExecStart=/usr/sbin/fix-efi.sh
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
END
cat > /usr/sbin/fix-efi.sh <<END
#!/usr/bin/env bash
if efivar --list > /dev/null ; then
  grub-install --removable --target=x86_64-efi --efi-directory=/boot --recheck && systemctl disable fix-efi.service
  grub-mkconfig -o /boot/grub/grub.cfg
  ROOT_DEVICE=\\\$(df | grep -w / | awk {'print \\\$1'})
  ROOT_FS_TYPE=\\\$(lsblk \\\${ROOT_DEVICE} -n -o FSTYPE)
  if [ "\\\$ROOT_FS_TYPE" = "f2fs" ] ; then
    fix-f2fs-grub.sh /boot/grub/grub.cfg
  fi
fi
END
chmod +x /usr/sbin/fix-efi.sh
systemctl enable fix-efi.service
grub-install --modules=part_gpt --target=i386-pc --recheck --debug ${TARGET_DEV}
EOF
if [ -b $DD_TO_DISK ] ; then
  for n in ${DD_TO_DISK}* ; do sudo umount $n || true; done
  sudo wipefs -a ${DD_TO_DISK}
fi
chmod +x /tmp/chroot.sh
sudo mv /tmp/chroot.sh ${TMP_ROOT}/root/chroot.sh
sudo arch-chroot ${TMP_ROOT} /root/chroot.sh
sudo rm ${TMP_ROOT}/root/chroot.sh
sudo cp "$THIS" /usr/sbin/mkarch.sh
sync && sudo umount ${TMP_ROOT}/boot && sudo umount ${TMP_ROOT} && sudo losetup -D && sync && echo "Image sucessfully created"
if [ -b $DD_TO_DISK ] ; then
  TARGET_DEV=$DD_TO_DISK
  echo "Writing image to disk..."
  sudo -E bash -c 'dd if='"${IMG_NAME}"' of='${TARGET_DEV}' bs=4M && sync && sgdisk -e '${TARGET_DEV}' && sgdisk -v '${TARGET_DEV}' && echo "Image sucessfully written."'
fi

if [ "$TARGET_IS_REMOVABLE" = true ] ; then
  sudo eject ${TARGET_DEV} && echo "It's now safe to remove $TARGET_DEV"
fi

if [ "$CLEAN_UP" = true ] ; then
  rm -f "${IMG_NAME}"
fi
