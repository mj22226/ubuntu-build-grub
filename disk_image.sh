#!/bin/bash
set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

#set -x

cleanup_loopdev() {
    local loop="$1"

    sync --file-system
    sync

    sleep 1

    if [ -b "${loop}" ]; then
        for part in "${loop}"p*; do
            if mnt=$(findmnt -n -o target -S "$part"); then
                umount "${mnt}"
            fi
        done
        losetup -d "${loop}"
    fi
}

wait_loopdev() {
    local loop="$1"
    local seconds="$2"

    until test $((seconds--)) -eq 0 -o -b "${loop}"; do sleep 1; done

    ((++seconds))

    ls -l "${loop}" &> /dev/null
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

export  LC_ALL=C 
export  LC_CTYPE=C
export  LANGUAGE=C
export  LANG=C

if [ ! -f ./rootfs ]; then 
	exit 1 
fi

. ./rootfs
. ./kernel_version

rootfs="$(readlink -f "$rootfs")"
if [[ "$(basename "${rootfs}")" != *".rootfs.tar" || ! -e "${rootfs}" ]]; then
    echo "Error: $(basename "${rootfs}") must be a rootfs tarfile"
    exit 1
fi


# Create an empty disk image
now=`date +%F`
img="./Ubuntu-${kernel_version}-$2-$now.img"
size="$(( $(wc -c < "${rootfs}" ) / 1024 / 1024 ))"
truncate -s "$(( size + 1024 ))M" "${img}"

# Create loop device for disk image
loop="$(losetup -f)"
losetup -P "${loop}" "${img}"
disk="${loop}"

# Cleanup loopdev on early exit
trap 'cleanup_loopdev ${loop}' EXIT

# Ensure disk is not mounted
mount_point=/tmp/mnt
umount "${disk}"* 2> /dev/null || true
umount ${mount_point}/* 2> /dev/null || true
mkdir -p ${mount_point}

    # Setup partition table
    dd if=/dev/zero of="${disk}" count=4096 bs=512
    parted --script "${disk}" \
    mklabel gpt \
    mkpart "ESP" fat32 16MiB 428MiB \
    set 1 esp on \
    mkpart "rootfs" ext4 428MiB 100%

    # パーティションIDの明示的設定
    {
        echo "t"
        echo "1"
        echo "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" # EFI System
        echo "t"
        echo "2"
        echo "0FC63DAF-8483-4772-8E79-3D69D8477DE4" # Linux Root
        echo "w"
    } | fdisk "${disk}" &> /dev/null || true


    partition_char="$(if [[ ${disk: -1} == [0-9] ]]; then echo p; fi)"

    boot_part="${disk}${partition_char}1"
    root_part="${disk}${partition_char}2"


    wait_loopdev "${disk}${partition_char}1" 60 || {
        echo "Failure to create ${disk}${partition_char}1 in time"
        exit 1
    }

    wait_loopdev "${disk}${partition_char}2" 60 || {
        echo "Failure to create ${disk}${partition_char}1 in time"
        exit 1
    }

    sleep 1

    # Generate random uuid for bootfs
    fat_uuid=$(uuidgen | head -c8 | tr '[:lower:]' '[:upper:]')
    root_uuid=$(uuidgen)
    boot_uuid="${fat_uuid: 0:4}-${fat_uuid: -4:4}"

echo "boot_uuid=$boot_uuid"
echo "root_uuid=$root_uuid"
echo "fat_uuid=$fat_uuid"

    # 第1パーティション (FAT32 /boot)
    mkfs.vfat -i "${fat_uuid}" -n "BOOT" "${boot_part}"

    # 第2パーティション (Ext4 /)
    mkfs.ext4 -U "${root_uuid}" -L "rootfs" "${root_part}"

 # --- マウントと展開セクション ---
    mkdir -p ${mount_point}/root
    mount "${root_part}" ${mount_point}/root

 # /boot をマウントして中身を移動（もしtar内に/bootがある場合）
    mkdir -p ${mount_point}/root/boot
    mount "${boot_part}" ${mount_point}/root/boot

# Copy the rootfs to root partition
tar -xpf "${rootfs}" -C ${mount_point}/root || true


fdt_name="/device-tree/rockchip/$3.dtb"

dtbs_install_path="/usr/lib/firmware/${kernel_version}"

if [ ! -f ${mount_point}/root${dtbs_install_path}${fdt_name} ]; then
	echo "${dtbs_install_path}${fdt_name} not found"
	exit 1
fi



# Create fstab entries
cat <<EOF > ${mount_point}/root/etc/fstab
# <file system> <mount point> <type> <options> <dump> <fsck>
UUID=${root_uuid} /      	ext4 defaults,noatime,x-systemd.growfs 0 1
UUID=${boot_uuid} /boot 	vfat defaults 0 2
EOF

# Write bootloader to disk image
if [ -f "u-boot-rockchip.bin" ]; then
    dd if="u-boot-rockchip.bin" of="${loop}" seek=1 bs=32k conv=fsync
else
	echo "u-boot-rockchip.bin not found"
	exit 1
fi

#mount --bind /dev  "${mount_point}/root/dev"
#mount --bind /proc "${mount_point}/root/proc"
#mount --bind /sys  "${mount_point}/root/sys"

mount dev-live -t devtmpfs "$mount_point/root/dev"
mount devpts-live -t devpts -o nodev,nosuid "$mount_point/root/dev/pts"
mount proc-live -t proc "$mount_point/root/proc"
mount sysfs-live -t sysfs "$mount_point/root/sys"
mount securityfs -t securityfs "$mount_point/root/sys/kernel/security"
# --- GRUBインストール実行 ---
chroot ${mount_point}/root /bin/bash -c "
    set -e

    grub-install --target=arm64-efi --efi-directory=/boot

    # 2. 設定ファイルの更新
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub

    update-grub
"

# --- 後片付け ---
umount "$mount_point/root/sys/kernel/security"
umount "$mount_point/root/sys"
umount "$mount_point/root/proc"
umount "$mount_point/root/dev/pts"
umount "$mount_point/root/dev"

#umount "${mount_point}/root/sys"
#umount "${mount_point}/root/proc"
#umount "${mount_point}/root/dev"

DTB_FILENAME="$3.dtb"

cat << 'EOF' > ${mount_point}/root/etc/kernel/postinst.d/zzzz-arm64-grub-dtb-fix
#!/bin/bash
# $1 は apt が渡すカーネルバージョン (例: 6.18.25-rockchip)
KVER="$1"
DTB_NAME="DTB_FILENAME_PLACEHOLDER"
DTB_SRC="/usr/lib/firmware/${KVER}/device-tree/rockchip/${DTB_NAME}"
BOOT_DEST="/boot/rockchip/${KVER}"

# 1. DTBをバージョン専用ディレクトリにコピー
if [ -f "${DTB_SRC}" ]; then
    mkdir -p "${BOOT_DEST}"
    cp "${DTB_SRC}" "${BOOT_DEST}/${DTB_NAME}"
fi

# 2. grub.cfg を更新（標準状態に戻る）
#update-grub

# 3. 全てのカーネルエントリーに対して devicetree 行を自動挿入
# grub.cfg内の全「linux /vmlinuz-バージョン」を探し、
# その直後の「initrd」の前に、対応する「devicetree」を差し込む
if [ -f /boot/grub/grub.cfg ]; then
    # 既存の devicetree 行を一旦全て削除（二重登録防止）
    sed -i '/devicetree \/rockchip\//d' /boot/grub/grub.cfg
    
    # 全ての vmlinuz 行をスキャンして、対応する devicetree 行を挿入
    # 検索: linux /vmlinuz-(.+)  -> 置換: linux ... \n devicetree /rockchip/\1/DTB
    sed -i -E "s|(linux[[:space:]]+/vmlinuz-([^[:space:]]+).+)| \1\n\tdevicetree /rockchip/\2/${DTB_NAME}|" /boot/grub/grub.cfg
fi
EOF

# プレースホルダーを実際のファイル名に置換
sed -i "s/DTB_FILENAME_PLACEHOLDER/${DTB_FILENAME}/" ${mount_point}/root/etc/kernel/postinst.d/zzzz-arm64-grub-dtb-fix

chmod +x ${mount_point}/root/etc/kernel/postinst.d/zzzz-arm64-grub-dtb-fix
echo GRUB_CMDLINE_LINUX='"'"$(cat ${mount_point}/root/etc/kernel/cmdline)"'"' >> ${mount_point}/root/etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="text"/' ${mount_point}/root/etc/default/grub

mkdir -p ${mount_point}/root/boot/rockchip/$kernel_version
cp ${mount_point}/root${dtbs_install_path}${fdt_name} ${mount_point}/root/boot/rockchip/$kernel_version
sed -i -E "s|(linux[[:space:]]+/vmlinuz-([^[:space:]]+).+)| \1\n\tdevicetree /rockchip/\2/$3.dtb|" ${mount_point}/root/boot/grub/grub.cfg

sync --file-system
sync

# Umount partitions
umount ${mount_point}/root/boot
umount ${mount_point}/root



# Remove loop device
losetup -d "${loop}"

# Exit trap is no longer needed
trap '' EXIT

echo -e "\nCompressing $(basename "${img}.xz")\n"
xz -v -9 -T0 "${img}"
#rm "${img}"
#cd ./images && sha256sum "$(basename "${img}.xz")" > "$(basename "${img}.xz.sha256")"
echo "Finush"
exit 0
