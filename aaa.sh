# force to be root
sudo echo ""

MANIFEST_URL=http://jfumgbuild-depot.jf.intel.com/build/eng-builds/main/PSI/weekly/2012_WW28/manifest-MAIN-2012_WW28-generated.xml
MANIFEST_FILE=manifest-MAIN-2012_WW28-generated.xml
PROJECT_DIR=~/LOCAL/STABLE
FASTBOOT_DIR=axel_fastboot
FASTBOOT_REF=$HOME/.flasher/.download/r3/weekly/2012_WW28/MFLD_PRx/flash_files/build-eng/mfld_prx-eng-fastboot-r3-weekly-331
FASTBOOT_REF=~/.flasher/.download/r3/weekly/2012_WW22/mfld_prx-eng-fastboot-main-weekly-191
OUT=out/target/product/mfld_pr2
MY_KERNEL=$PROJECT_DIR/$OUT/axel_kernel
MY_BOOT_DIR=$PROJECT_DIR/$OUT/axel_boot
MY_RAMDISK=$PROJECT_DIR/$OUT/axel_ramdisk
PLATFORM=mfld_pr2
BRCM_MODULE=$PROJECT_DIR/hardware/broadcom/wlan/bcm43xx/open-src/src/dhd/linux/dhd-cdc-sdmmc-android-panda-icsmr1-cfg80211-oob-3.0.8/bcmdhd.ko
CUR_DIR=$PWD

ARG1=$1
ARG2=$2
ARG3=$3
ARG4=$4
ARG5=$5


###############################################################################
# HELPERS 
###############################################################################

print()
{
	echo "#######################################################"
	echo $1
	echo "#######################################################"
}

exit_if_no_file()
{
	if [ ! -e $1 ]; then
		print "$1 does not exists. Abort"
		exit 1;
	fi
}

exit_if_file()
{
	if [ -e $1 ]; then
		print "$1 exists. Abort PLEASE REMOVE rm -rf $1"
		exit 1;
	fi
}

check()
{
	SS=`df -h|grep sda3|awk '{printf $4}'|awk 'BEGIN{FS="G"}{printf $1}'`
	echo "$SS"

}

goto_project()
{
	cd $PROJECT_DIR
}

init()
{
	print "project: $PROJECT_DIR"
	cd $PROJECT_DIR
	rm $HOME/project
	rm $PROJECT_DIR/kernel
	rm $PROJECT_DIR/outp

	ln -s $PROJECT_DIR $HOME/project
	ln -s $PROJECT_DIR/hardware/intel/linux-2.6 kernel
	ln -s $PROJECT_DIR/$OUT outp
}

###############################################################################
# INIT FROM MAINIFEST
###############################################################################
new_project()
{
	exit_if_file $PROJECT_DIR 

	mkdir $PROJECT_DIR
	cd $PROJECT_DIR

	print "REPO INIT $MANIFEST_FILE"
	repo init -u git://android.intel.com/manifest -b platform/android/main -m android-main

	print "SETTING MAINFEST $MANIFEST_FILE"
	wget $MANIFEST_URL
	sed -i 's/jfumg-gcrmirror.jf.intel.com/ncsgit001.nc.intel.com/g' ./$MANIFEST_FILE
	cp  $MANIFEST_FILE ./.repo/manifests
	repo init -m  $MANIFEST_FILE

	print "REPO SYNC"
	repo sync

	#Check that sync worked and try again if not.
	if [ ! -e $PROJECT_DIR/frameworks ]; then
		print "REPO SYNC FAILED, TRYING AGAIN"
		rm -rf $PROJECT_DIR
		new_project;
	fi

	print "BUILDING SYSTEM"
	source build/envsetup.sh
	lunch $PLATFORM-eng
	make -j8 $PLATFORM
	make_kernel;
	make_ramdisk;
	
}






###############################################################################
# MAKERS
###############################################################################
make_kernel()
{
	cd $PROJECT_DIR/hardware/intel/linux-2.6
	KFLAGS="ARCH=x86 CROSS_COMPILER=/home/axelh/LOCAL/toolchain/i686-android-linux-4.4.3/bin/i686-android-linux- -j8 O=$MY_KERNEL"

	if [ ! -e $MY_KERNEL ]; then
		mkdir $MY_KERNEL
		cp $PROJECT_DIR/$OUT/kernel_build/.config $MY_KERNEL
	fi		
	
	print "BUILD KERNEL"
	rm $MY_KERNEL/arch/x86/boot/bzImage
	make $KFLAGS bzImage	
	if [ ! -e $MY_KERNEL/arch/x86/boot/bzImage ]; then
		print "KERNEL BUILD ERROR"
		exit
	fi

	if [ ! -e $MY_BOOT_DIR ]; then
		mkdir $MY_BOOT_DIR
	fi
	cp $MY_KERNEL/arch/x86/boot/bzImage $MY_BOOT_DIR

	make $KFLAGS modules
	find  $MY_KERNEL -iname "*.ko" -exec cp "{}" $MY_RAMDISK/lib/modules \;

	make_ramdisk;
	make_bootimage;
}

make_ramdisk()
{
	print "make_ramdisk"
	if [ ! -e $MY_BOOT_DIR ]; then
		mkdir $MY_BOOT_DIR
	fi

	if [ ! -e $MY_RAMDISK ]; then
		mkdir $MY_RAMDISK
		cd $MY_RAMDISK
		gunzip -c ../ramdisk.img | cpio -i
	fi

	cp $BRCM_MODULE $MY_RAMDISK/lib/modules

	cd $MY_RAMDISK
	find . | cpio -o -H newc | gzip > $MY_BOOT_DIR/my_ramdisk.img
	make_bootimage;	
}

make_bootimage()
{
	print "make_bootimage"
	cd $PROJECT_DIR

	exit_if_no_file $MY_BOOT_DIR/my_ramdisk.img
	exit_if_no_file $MY_BOOT_DIR/bzImage
	rm $MY_BOOT_DIR/boot.bin

	source build/envsetup.sh

	vendor/intel/support/mkbootimg \
--cmdline "init=/init pci=noearly console=ttyS0 console=logk0 earlyprintk=nologger loglevel=8 hsu_dma=7 kmemleak=off androidboot.bootmedia=sdcard androidboot.hardware=mfld_pr2 ip=50.0.0.2:50.0.0.1::255.255.255.0::usb0:on" \
--ramdisk $MY_BOOT_DIR/my_ramdisk.img \
--kernel $MY_BOOT_DIR/bzImage \
--output $OUT/axel_boot/boot.bin \
--product $PLATFORM --type mos

}

make_fastboot_dir()
{
	print "Creating fastboot dir form $FASTBOOT_REF"
	rm -rf $PROJECT_DIR/$OUT/$FASTBOOT_DIR
	mkdir $PROJECT_DIR/$OUT/$FASTBOOT_DIR
	cp -rf $FASTBOOT_REF/* $PROJECT_DIR/$OUT/$FASTBOOT_DIR
	cd $PROJECT_DIR/$OUT/$FASTBOOT_DIR
	FB_OTA_FILE=`ls *-ota-*.zip`

	cd $PROJECT_DIR/$OUT
	MY_OTA_FILE=`ls *-ota-*.zip`

	cp $PROJECT_DIR/$OUT/$MY_OTA_FILE $PROJECT_DIR/$OUT/$FASTBOOT_DIR/$FB_OTA_FILE
}


make_broadcom()
{
	cd $PROJECT_DIR
	rm $BRCM_MODULE
	rm $MY_RAMDISK/lib/modules/bcmdhd.ko

	vendor/intel/support/bcm43xx-build.sh
	exit_if_no_file $BRCM_MODULE

	cp $BRCM_MODULE $MY_RAMDISK/lib/modules
	exit_if_no_file $MY_RAMDISK/lib/modules

	make_ramdisk;
	make_bootimage;
}





###############################################################################
# FLASHERS
###############################################################################

flash_my_boot()
{
	exit_if_no_file $MY_BOOT_DIR/boot.bin
#	adb reboot bootloader
	adb reboot recovery
	fastboot flash boot $MY_BOOT_DIR/boot.bin
	fastboot continue
}

flash_this()
{

	cd $CUR_DIR
	adb reboot recovery
	fastboot erase data;
	fastboot erase system;
	fastboot erase boot;
	fastboot flash boot boot.bin ;
	fastboot flash system system.tar.gz ;
	fastboot continue


}


flash_my_build()
{
	exit_if_no_file $MY_BOOT_DIR/boot.bin
	exit_if_no_file $PROJECT_DIR/$OUT/system.tar.gz

	adb reboot recovery
	fastboot erase system
	fastboot erase data
	fastboot erase boot
	fastboot flash boot $MY_BOOT_DIR/boot.bin
	fastboot flash system $PROJECT_DIR/$OUT/system.tar.gz
	fastboot continue
}



###############################################################################
# POWER
###############################################################################
power_on(){
phy 5 on
}
power_off(){
phy 5 off
}
power_restart(){
power_off;sleep 2;power_on
}
usb_on(){
phy 4 on
}
usb_off(){
phy 4 off
}


###############################################################################
# RUNNERS
###############################################################################
run_syncer()
{
	while [ ! -z "$1" ]; do
		cd $CUR_DIR
		repo sync
		lunch $PLATFORM-eng
	        make -j8 $PLATFORM
		sleep 3600
	done
		
}




usage()
{
echo "
USAGE IS:
	mn)	new_project;break;;
	mk)	make_kernel;break;;
	mf)	make_fastboot_dir;break;;
	mb)	make_bootimage;break;;
	mq)	make_broadcom;break;;
	mr)	make_ramdisk;break;;
	fb)	flash_my_boot;break;;
	ff)	flash_my_build;break;;
	po)	power_on;break;;
	pf)	power_off;break;;
	pr)	power_restart;break;;
	uo)	usb_on;break;;
	uf)	usb_off;break;;
	cd)	goto_project;break;;
	c)	check;break;;
	e)	vim ~/tools/aaa.sh;break;;
	*)	usage;break;;

"
}
###############################################################################
# MAIN
###############################################################################
if [ -z "$1" ]; then
        usage
        exit
fi

#local init function 
init;

while [ ! -z "$1" ]; do
	case $1 in
	mn)	new_project;break;;
	mk)	make_kernel;break;;
	mf)	make_fastboot_dir;break;;
	mb)	make_bootimage;break;;
	mq)	make_broadcom;break;;
	mr)	make_ramdisk;break;;

	fb)	flash_my_boot;break;;
	ff)	flash_my_build;break;;
	ft)	flash_this;break;;

	po)	power_on;break;;
	pf)	power_off;break;;
	pr)	power_restart;break;;
	uo)	usb_on;break;;
	uf)	usb_off;break;;
	cd)	goto_project;break;;
	
	rs)	run_syncer;break;;

	c)	check;break;;
	e)	vim ~/tools/aaa.sh;break;;
	*)	usage;break;;
	esac
	shift
done


echo "done"







