#!/usr/bin/env bash

# file names & paths
tmp="$HOME"  # destination folder to store the final iso file
hostname="ubuntu"
currentuser="$( whoami)"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

function usage {
    echo " +--------------------------------------------------------+"
    echo " |                                                        |"
    echo " | --debug        step through the script, await <enter>  |"
    echo " | --help, -h     displays this output                    |"
    echo " |                                                        |"
    echo " | Example:                                               |"
    echo " |    1)  ./create-unattended-iso.sh                      |"
    echo " |    2)  ./create-unattended-iso.sh --debug              |"
    echo " |    3)  ./create-unattended-iso.sh --h                  |"
    echo " |    4)  ./create-unattended-iso.sh --help               |"
    echo " |                                                        |"
    echo " +--------------------------------------------------------+"
}

function breakpoint {
    if [DEBUG]; then
        echo " +---------------------------+"
        echo " | press any key to continue |"
        echo " +---------------------------+"
        while [ true ] ; do
            read -t 3 -n 1
            # if input == ESC key
            if [ $? = 0 ];
                then
                break;
            fi
        done
    fi
}

function debug_msg {
    if [DEBUG]; then
        printf $1
    fi
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# Get Flags/Arguments
DEBUG=false
while [ "$1" != "" ]; do
    case $1 in
    --debug)
        DEBUG=true
        ;;
    -h | --help)
        usage # run usage function
        ;;
    *)
        continue
        ;;
    esac
    shift # remove the current value for `$1` and use the next
done

# ask if script runs without sudo or root priveleges

debug_msg " is currentuser root?"

if [ $currentuser != "root" ]; then
    printf "\n :ERROR: you need sudo privileges to run this script, or run it as root\n"
    exit 1
else
    debug_msg " : TRUE\n"
fi

breakpoint #Debug breakpoint

#check that we are in ubuntu 16.04+

case "$(lsb_release -rs)" in
    16*|18*) ub1604="yes" ;;
    *) ub1604="" ;;
esac

#get the latest versions of Ubuntu LTS
debug_msg " getting latest versions of ubuntu"

tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1

debug_msg " : DONE\n"
breakpoint #Debug breakpoint

# create the menu based on available versions from
# http://cdimage.ubuntu.com/releases/
# http://releases.ubuntu.com/

debug_msg " generating menu\n"

WORKFILE=www.list
EXCLUDE_LIST='torrent|zsync|live'
COUNTER=1
if [ ! -z $1 ] && [ $1 == "rebuild" ]; then
    rm -f ${WORKFILE}
fi
if [ ! -e ${WORKFILE} ]; then
     echo Building menu from available builds
     for version in $(wget -qO - http://cdimage.ubuntu.com/releases/ | grep -oP href=\"[0-9].* | cut -d'"' -f2 | tr -d '/'); do
        TITLE=$(wget -qO - http://cdimage.ubuntu.com/releases/${version}/release | grep h1 | sed s'/^ *//g' | sed s'/^.*\(Ubuntu.*\).*$/\1/' | sed s'|</h1>||g')
        CODE=$(echo ${TITLE} | cut -d "(" -f2 | tr -d ")")
        URL=http://releases.ubuntu.com/${version}/
        wget -qO - ${URL} | grep server | grep amd64 | grep -v "${EXCLUDE_LIST}" > /dev/null
        if [ $? -ne 0 ] ; then
            URL=http://cdimage.ubuntu.com/releases/${version}/release/
        fi
        FILE=$(wget -qO - ${URL} | grep server-amd64 | grep -o ubuntu.*.iso | grep -v "${EXCLUDE_LIST}" | grep ">" | cut -d ">" -f2 | sort -u)
        FILE=$(echo ${FILE} | tr "\n" " " | tr "\r" " ")
        if [[ ! -z ${FILE} ]] && [[ ! -z ${TITLE} ]]; then
            echo ${TITLE}
            for iso in ${FILE}; do
                ver=$(echo ${iso} | cut -d- -f2)
                if [ ! -e ${WORKFILE} ] || ! grep -q "${ver} " ${WORKFILE}; then
                    echo "${COUNTER} ${ver} ${URL} ${iso} \"${CODE}\"" >> ${WORKFILE}
                    ((COUNTER++))
                fi
            done
        fi
     done | uniq
fi

breakpoint #Debug breakpoint

# display the menu for user to select version
echo
MIN=1
MAX=$(tail -1 ${WORKFILE} | awk '{print $1}')
ubver=0
while [ ${ubver} -lt ${MIN} ] || [ ${ubver} -gt ${MAX} ]; do
    echo " which ubuntu edition would you like to remaster:"
    echo
    cat ${WORKFILE} | while read A B C D E; do
        echo " [$A] Ubuntu $B ($E)"
    done
    echo
    read -p " please enter your preference: [${MIN}-${MAX}]: " ubver
done

download_file=$(grep -w ^$ubver ${WORKFILE} | awk '{print $4}')           # filename of the iso to be downloaded
download_location=$(grep -w ^$ubver ${WORKFILE} | awk '{print $3}')     # location of the file to be downloaded
new_iso_name="ubuntu-$(grep -w ^$ubver ${WORKFILE} | awk '{print $2}')-server-amd64-unattended.iso" # filename of the new iso file to be created

breakpoint #Debug breakpoint

if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

breakpoint #Debug breakpoint

# ask the user questions about his/her preferences
read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "netson" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2
printf "\n"
while [[ "$password" != "$password2" ]]; do # check if the passwords match to prevent headaches
    echo " Ope! Your passwords didn't match"
    read -sp " --   Enter it again: " password
    printf "\n"
    read -sp " -- Confirm it again: " password2
    printf "\n"
done
read -ep " Make ISO bootable via USB: " -i "yes" bootable

breakpoint #Debug breakpoint

# download the ubuntu iso. If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
    echo "Error: Failed to download ISO: $download_location$download_file"
    echo "This file may have moved or may no longer exist."
    echo
    echo "You can download it manually and move it to $tmp/$download_file"
    echo "Then run this script again."
    exit 1
fi

breakpoint #Debug breakpoint

# download netson seed file
seed_file="netson.seed"
if [[ ! -f $tmp/$seed_file ]]; then
    echo -n " downloading $seed_file: "
    download "https://raw.githubusercontent.com/netson/ubuntu-unattended/master/$seed_file"
fi

breakpoint #Debug breakpoint

# Check which OS
for i in $( echo rpm dpkg pacman ); do 
    os=$(which $i);
    case $os in 
        # install required packages
        *dpkg)
            echo " installing required packages"
            if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
                (apt-get -y update > /dev/null 2>&1) &
                spinner $!
                (apt-get -y install whois genisoimage > /dev/null 2>&1) &
                spinner $!
            fi
            if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
                if [ $(program_is_installed "isohybrid") -eq 0 ]; then
                #16.04
                if [[ $ub1604 == "yes" || $(lsb_release -cs) == "artful" ]]; then
                    (apt-get -y install syslinux syslinux-utils > /dev/null 2>&1) &
                    spinner $!
                else
                    (apt-get -y install syslinux > /dev/null 2>&1) &
                    spinner $!
                fi
                fi
            fi
            break
            ;;
        *rpm)
            echo "rpm"
            echo " installing required packages"
            if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
                (dpkg -y update > /dev/null 2>&1) &
                spinner $!
                (dpkg -y install whois genisoimage > /dev/null 2>&1) &
                spinner $!
            fi
            if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
                if [ $(program_is_installed "isohybrid") -eq 0 ]; then
                #16.04
                if [[ $ub1604 == "yes" || $(grep -oP '(?<=\().*(?=\))' /etc/redhat-release) == "artful" ]]; then
                    (dpkg -y install syslinux syslinux-utils > /dev/null 2>&1) &
                    spinner $!
                else
                    (dpkg -y install syslinux > /dev/null 2>&1) &
                    spinner $!
                fi
                fi
            fi
            break
            ;;
        *pacman)
            echo "BTW ... you're using Arch"
            echo " installing required packages"
            if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
                (pacman -Syu > /dev/null 2>&1) &
                spinner $!
                (pacman -S whois genisoimage > /dev/null 2>&1) &
                spinner $!
            fi
            if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
                if [ $(program_is_installed "isohybrid") -eq 0 ]; then
                #16.04
                if [[ $ub1604 == "yes" || $(lsb_release -cs) == "artful" ]]; then
                    (pacman -S syslinux syslinux-utils > /dev/null 2>&1) &
                    spinner $!
                else
                    (pacman -S syslinux > /dev/null 2>&1) &
                    spinner $!
                fi
                fi
            fi
            break
            ;;
        *)
            continue
            ;;
    esac
done 2> /dev/null


breakpoint #Debug breakpoint


# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

breakpoint #Debug breakpoint

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi

breakpoint #Debug breakpoint

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

breakpoint #Debug breakpoint

# set the language for the installation menu
cd $tmp/iso_new
#doesn't work for 16.04
echo en > $tmp/iso_new/isolinux/lang

breakpoint #Debug breakpoint

#16.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso_new/isolinux/isolinux.cfg

breakpoint #Debug breakpoint

# set late command

   late_command="chroot /target curl -L -o /home/$username/start.sh https://raw.githubusercontent.com/netson/ubuntu-unattended/master/start.sh ;\
     chroot /target chmod +x /home/$username/start.sh ;"

# copy the netson seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

breakpoint #Debug breakpoint

# include firstrun script
echo "
# setup firstrun script
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

breakpoint #Debug breakpoint

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

breakpoint #Debug breakpoint

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

breakpoint #Debug breakpoint

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

breakpoint #Debug breakpoint

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall NETSON Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

breakpoint #Debug breakpoint

# add the autoinstall option to the menu for USB Boot
sed -i '/set timeout=30/amenuentry "Autoinstall Netson Ubuntu Server" {\n\	set gfxpayload=keep\n\	linux /install/vmlinuz append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed quiet ---\n\	initrd	/install/initrd.gz\n\}' $tmp/iso_new/boot/grub/grub.cfg
sed -i -r 's/timeout=[0-9]+/timeout=1/g' $tmp/iso_new/boot/grub/grub.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "NETSON_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

breakpoint #Debug breakpoint

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid $tmp/$new_iso_name
fi

breakpoint #Debug breakpoint

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml


# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
