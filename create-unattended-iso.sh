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
    if $DEBUG ; then
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
    if $DEBUG ; then
        printf "$1"
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

debug_msg " :DEBUG: is currentuser root?"

if [ $currentuser != "root" ]; then
    printf "\n :ERROR: you need sudo privileges to run this script, or run it as root\n"
    exit 1
else
    debug_msg " : TRUE\n"
fi

breakpoint #Debug breakpoint
debug_msg " :DEBUG: getting latest versions of ubuntu"

#get the latest versions of Ubuntu LTS
tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://releases.ubuntu.com/' >/dev/null 2>&1

debug_msg " : DONE\n"
breakpoint #Debug breakpoint

# create the menu based on available versions from
# http://cdimage.ubuntu.com/releases/
# http://releases.ubuntu.com/

debug_msg " :DEBUG: generating menu\n"

WORKFILE=www.list
EXCLUDE_LIST='torrent|zsync|live'
COUNTER=1
if [ ! -z $1 ] && [ $1 == "rebuild" ]; then
    rm -f ${WORKFILE}
fi
if [ ! -e ${WORKFILE} ]; then
    debug_msg "         "
    echo "Building menu from available builds"
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
        debug_msg "         "
        echo "${TITLE}"
        for iso in ${FILE}; do
            ver=$(echo "${iso}" | cut -d- -f2)
            if [ ! -e ${WORKFILE} ] || ! grep -q "${ver} " ${WORKFILE}; then
                debug_msg "         "
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
    debug_msg "         "
    echo " which ubuntu edition would you like to remaster:"
    echo
    cat ${WORKFILE} | while read A B C D E; do
        debug_msg "         "
        echo " [$A] Ubuntu $B ($E)"
    done
    echo
    debug_msg "         "
    read -p " please enter your preference: [${MIN}-${MAX}]: " ubver
done

download_file=$(grep -w "^$ubver" ${WORKFILE} | awk '{print $4}')           # filename of the iso to be downloaded
download_location=$(grep -w "^$ubver" ${WORKFILE} | awk '{print $3}')     # location of the file to be downloaded
new_iso_name="ubuntu-$(grep -w "^$ubver" ${WORKFILE} | awk '{print $2}')-server-amd64-unattended.iso" # filename of the new iso file to be created

breakpoint #Debug breakpoint
debug_msg " :DEBUG: getting default timezone info"


if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

debug_msg " \n"
breakpoint #Debug breakpoint


# ask the user questions about his/her preferences
debug_msg "         "
read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
debug_msg "         "
read -ep " please enter your preferred username: " -i "netson" username
debug_msg "         "
read -sp " please enter your preferred password: " password
printf "\n"
debug_msg "         "
read -sp " confirm your preferred password: " password2
printf "\n"
while [[ "$password" != "$password2" ]]; do # check if the passwords match to prevent headaches
    debug_msg "         "
    echo " Ope! Your passwords didn't match"
    debug_msg "         "
    read -sp " --   Enter it again: " password
    printf "\n"
    debug_msg "         "
    read -sp " -- Confirm it again: " password2
    printf "\n"
done
debug_msg "         "
read -ep " Make ISO bootable via USB: " -i "yes" bootable

breakpoint #Debug breakpoint

# download the ubuntu iso. If it already exists, do not delete in the end.
cd $tmp
debug_msg " :DEBUG: checking for $download_file\n"
if [[ ! -f $tmp/$download_file ]]; then
    debug_msg " :DEBUG: "
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
    debug_msg "         "
    echo "Error: Failed to download ISO: $download_location$download_file"
    debug_msg "         "
    echo "This file may have moved or may no longer exist."
    debug_msg "         "
    echo
    debug_msg "         "
    echo "You can download it manually and move it to $tmp/$download_file"
    debug_msg "         "
    echo "Then run this script again."
    exit 1
fi

breakpoint #Debug breakpoint
debug_msg " :DEBUG: checking for/Downloading preseed file\n"


# download netson seed file
seed_file="netson.seed"
if [[ ! -f $tmp/$seed_file ]]; then
    debug_msg " :DEBUG: "
    echo -n " downloading $seed_file: "
    download "https://raw.githubusercontent.com/netson/ubuntu-unattended/master/$seed_file"
fi

breakpoint #Debug breakpoint
debug_msg " :DEBUG: checking host OS & installing required packages\n"


# Check which OS
for i in $( echo rpm dpkg pacman ); do 
    os=$(which $i);
    case $os in 
        # install required packages
        *dpkg)
            debug_msg " :DEBUG:"
            echo " installing required packages"
            if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
                (apt-get -y update > /dev/null 2>&1) &
                spinner $!
                (apt-get -y install whois genisoimage > /dev/null 2>&1) &
                spinner $!
            fi
            
            #check that we are in ubuntu 16.04+
            case "$(lsb_release -rs)" in
                16*|18*) ub1604="yes" ;;
                *) ub1604="" ;;
            esac

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
            debug_msg " :DEBUG:"
            echo " installing required packages"
            (dpkg -y update > /dev/null 2>&1) &
            spinner $!
            (dpkg -y install whois genisoimage > /dev/null 2>&1) &
            spinner $!
            if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
                (dpkg -y install syslinux syslinux-utils > /dev/null 2>&1) &
                spinner $!
            fi
            break
            ;;
        *pacman)
            debug_msg " : BTW : ..."
            echo " you're using Arch"
            debug_msg " :DEBUG:"
            echo " installing required packages"
            (pacman -Syu > /dev/null 2>&1) &
            spinner $!
            (pacman -S whois genisoimage > /dev/null 2>&1) &
            spinner $!
            if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
                (pacman -S syslinux syslinux-utils > /dev/null 2>&1) &
                spinner $!
            fi
            break
            ;;
        *)
            continue
            ;;
    esac
done 2> /dev/null


breakpoint #Debug breakpoint
debug_msg " :DEBUG: creating working folders\n"



# create working folders
debug_msg " :DEBUG:"
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso-org
mkdir -p $tmp/iso-new

breakpoint #Debug breakpoint
debug_msg " :DEBUG: mounting the image\n"
out_var=$(grep -qs "$tmp/iso-org" /proc/mounts)
debug_msg " :DEBUG: Output ${out_var}"

# mount the image
if grep -qs "$tmp/iso-org" /proc/mounts ; then
    debug_msg "         "
    echo " image is already mounted, continue"
else
    out_var=$(ls -al $tmp/$download_file)
    debug_msg " :DEBUG: Output : ls -al $tmp/$download_file \n${out_var}"
    out_var=$(ls -al $tmp/iso-org)
    debug_msg " :DEBUG: Output : ls -al $tmp/iso-org \n${out_var}"
    (mount -o loop $tmp/$download_file $tmp/iso-org > /dev/null 2>&1)
fi

breakpoint #Debug breakpoint
debug_msg " :DEBUG: copying iso contents to $tmp/iso-new\n"


# copy the iso contents to the working directory
out_var=$(ls -al $tmp/iso-new)
debug_msg " :DEBUG: Output : ls -al $tmp/iso-new (Before)\n${out_var}"
(cp -r $tmp/iso-org/* $tmp/iso-new > /dev/null 2>&1) &
spinner $!
out_var=$(ls -al $tmp/iso-new)
debug_msg " :DEBUG: Output : ls -al $tmp/iso-new (After)\n${out_var}"

breakpoint #Debug breakpoint
debug_msg " :DEBUG: setting language\n"


# set the language for the installation menu
cd $tmp/iso-new
#doesn't work for 16.04
echo "en" > $tmp/iso-new/isolinux/lang

breakpoint #Debug breakpoint
debug_msg " :DEBUG: updating timeout settings\n"


#16.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso-new/isolinux/isolinux.cfg

breakpoint #Debug breakpoint
debug_msg " :DEBUG: setting 'late' command\n"


# set late command

late_command="chroot /target curl -L -o /home/$username/start.sh https://raw.githubusercontent.com/netson/ubuntu-unattended/master/start.sh ;\
    chroot /target chmod +x /home/$username/start.sh ;"

debug_msg " :DEBUG: copying the preseed file to $tmp/iso-new/preseed/$seed_file\n"

# copy the netson seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso-new/preseed/$seed_file

breakpoint #Debug breakpoint
debug_msg " :DEBUG: updating the preseed file\n"


# include firstrun script
echo "
# setup firstrun script
d-i preseed/late_command                                    string      $late_command" >> $tmp/iso-new/preseed/$seed_file

breakpoint #Debug breakpoint
debug_msg " :DEBUG: generating password hash\n"


# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

breakpoint #Debug breakpoint
debug_msg " :DEBUG: updating preseed file with user choices\n"
debug_msg " :DEBUG:   - username: $username\n"
debug_msg " :DEBUG:   -   pwhash: $pwhash\n"
debug_msg " :DEBUG:   - hostname: $hostname\n"
debug_msg " :DEBUG:   - timezone: $timezone\n"


# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso-new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso-new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso-new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso-new/preseed/$seed_file

breakpoint #Debug breakpoint
debug_msg " :DEBUG: calculating checksum for seed file\n"


# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso-new/preseed/$seed_file)

breakpoint #Debug breakpoint
debug_msg " :DEBUG: adding the autoinstall option to the menu\n"


# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall NETSON Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed preseed/file/checksum=$seed_checksum --" $tmp/iso-new/isolinux/txt.cfg

breakpoint #Debug breakpoint
debug_msg " :DEBUG: adding the autoinstall option to the menu for USB Boot\n"


# add the autoinstall option to the menu for USB Boot
sed -i '/set timeout=30/amenuentry "Autoinstall Netson Ubuntu Server" {\n\	set gfxpayload=keep\n\	linux /install/vmlinuz append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed quiet ---\n\	initrd	/install/initrd.gz\n\}' $tmp/iso-new/boot/grub/grub.cfg
sed -i -r 's/timeout=[0-9]+/timeout=1/g' $tmp/iso-new/boot/grub/grub.cfg

breakpoint #Debug breakpoint
debug_msg " :DEBUG:"

echo " creating the remastered iso"
cd $tmp/iso-new
(mkisofs -D -r -V "NETSON_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

breakpoint #Debug breakpoint

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    debug_msg " :DEBUG: making iso USB bootable\n"
    isohybrid $tmp/$new_iso_name
fi

breakpoint #Debug breakpoint
debug_msg " :DEBUG: cleaning up\n"
debug_msg " :DEBUG:   - unmounting : $tmp/iso-org\n"
debug_msg " :DEBUG:   -   deleting : $tmp/iso-new\n"
debug_msg " :DEBUG:   -   deleting : $tmp/iso-org\n"
debug_msg " :DEBUG:   -   deleting : $tmphtml\n"


# cleanup
umount $tmp/iso-org
rm -rf $tmp/iso-new
rm -rf $tmp/iso-org
rm -rf $tmphtml


# print info to user
printf " "
debug_msg "---------"
echo "-----"
debug_msg "         "
echo " finished remastering your ubuntu iso file"
debug_msg "         "
echo " the new file is located at: $tmp/$new_iso_name"
debug_msg "         "
echo " your username is: $username"
debug_msg "         "
echo " your password is: $password"
debug_msg "         "
echo " your hostname is: $hostname"
debug_msg "         "
echo " your timezone is: $timezone"
echo

debug_msg " :DEBUG: unsetting vars\n"
debug_msg " :DEBUG:   - username\n"
debug_msg " :DEBUG:   - password\n"
debug_msg " :DEBUG:   - hostname\n"
debug_msg " :DEBUG:   - timezone\n"
debug_msg " :DEBUG:   - pwhash\n"
debug_msg " :DEBUG:   - download_file\n"
debug_msg " :DEBUG:   - download_location\n"
debug_msg " :DEBUG:   - new_iso_name\n"
debug_msg " :DEBUG:   - tmp\n"
debug_msg " :DEBUG:   - seed_file\n"

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
