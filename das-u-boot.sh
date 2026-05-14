#!/bin/bash

sudo apt-get update && sudo apt-get -y install  build-essential gcc-aarch64-linux-gnu bison \
qemu-user-static qemu-system-arm qemu-efi-aarch64 binfmt-support \
debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
udev dosfstools uuid-runtime git-lfs device-tree-compiler python3 \
python-is-python3 fdisk bc debhelper python3-pyelftools python3-setuptools \
python3-pkg-resources swig libfdt-dev libpython3-dev gawk \
git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex \
libelf-dev bison libgnutls28-dev libdw-dev \
dfu-util efitools gdisk graphviz imagemagick \
libgnutls28-dev libguestfs-tools libncurses-dev \
libsdl2-dev lz4 lzma lzma-alone openssl \
pkg-config python3-asteval python3-coverage python3-filelock \
python3-pkg-resources python3-pycryptodome \
python3-pytest python3-pytest-xdist python3-sphinxcontrib.apidoc \
python3-sphinx-rtd-theme python3-subunit python3-testtools \
python3-venv swig uuid-dev


	rm -rf arm64
	mkdir arm64
mem_size=`free --giga|grep Mem|awk '{print $2}'`
if [ $mem_size -gt 2 ]; then
        sudo mount -t tmpfs -o size=1G tmpfs arm64
fi
	cd arm64

		git clone --depth 1 https://github.com/rockchip-linux/rkbin
		
		DDR=`ls rkbin/bin/rk35/rk3568_ddr_1560MHz_v*.bin`
		BL31=`ls rkbin/bin/rk35/rk3568_bl31_v*.elf`
	export BL31=`pwd`/$BL31
	export ROCKCHIP_TPL=`pwd`/$DDR
echo ""
echo "export ROCKCHIP_TPL=$ROCKCHIP_TPL"
echo "export BL31=$BL31"
echo ""
		export PATH=`pwd`/tools/binman:$PATH
echo ""
echo "PATH=$PATH"
echo ""

		git clone --depth 1 https://gitlab.com/u-boot/u-boot.git -b v2026.04
		cd u-boot
		if [ ! -f configs/$1 ]; then
			echo "$1 not found in configs"
			cd ..
			exit 1
		fi

	echo 'CONFIG_SYS_SOC="rk3588"' >> configs/$1
        echo 'CONFIG_CMD_BOOTEFI=y' >> configs/$1
        echo 'CONFIG_EFI_LOADER=y' >> configs/$1
        echo 'CONFIG_BLK=y' >> configs/$1
        echo 'CONFIG_PARTITIONS=y' >> configs/$1

sed -i 's/#ifndef CONFIG_XPL_BUILD/#ifndef CONFIG_XPL_BUILD\n\n #define BOOT_TARGETS    "nvme scsi"\n\n/' include/configs/rockchip-common.h

		make distclean $1
		make -j8
		cp u-boot-rockchip.bin ../..
		cp u-boot-rockchip-spi.bin ../..
	echo "dd if=u-boot-rockchip.bin of=/dev/sdX seek=1 bs=32k conv=fsync"
	cd ../..
echo "DISK usage"
df arm64
if [ $mem_size -gt 2 ]; then
        sudo umount arm64
	sleep 2
fi 
exit 0

