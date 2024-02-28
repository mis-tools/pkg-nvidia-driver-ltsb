#!/usr/bin/env bash
set -ex

BUILD_NUMBER=$1
script_dir=$(dirname "$0")
cd ${script_dir}/..

version="352.55"    # known to be stable
version="352.63"    # never used
version="352.79"    # never used
version="361.28"    # 20160211, never used
version="361.42"    # 20160510, never used
version="361.45.11" # 20160525, never used
version="367.18"    # 20160614, never used
version="367.27"    # 20160704, never used
version="367.35"    # 20160715, never used
version="367.44"    # 20160906, never used
version="367.57"    # 20161014, never used
version="375.20"    # 20161125, never used
version="375.26"    # 20170106, never used
version="375.39"    # 20170505, never used
version="375.66"    # 20170505, NR 2.2.9
version="375.82"    # 20170817, never used
version="418.56"    # 20190321, never used
version="430.50"    # 20190911, NR 2.4.0
version="440.100"   # 20200228, NR 2.5.0
version="460.73.01" # 20210504, NR 2.6.0
version="470.57.02" # 20210802, NR 2.6.1
version="510.47.03" # 20220209, never used
version="510.54"    # 20220315, never used
version="510.60.02" # 20220325, never used
version="510.68.02" # 20220503, never used
version="510.73.05" # 20220518, never used
version="510.85.02" # 20220803, NR 2.7.0
version="515.65.01" # 20220920, never used

# Security Bulletin November 2022:
# https://nvidia.custhelp.com/app/answers/detail/a_id/5415
version="515.86.01" # 20221205, never used

# Security Bulletin March 2023:
# https://nvidia.custhelp.com/app/answers/detail/a_id/5452
version="525.105.17" # 20230331, NR 2.7.1

# Forum Announcement 20240224:
# https://forums.developer.nvidia.com/t/linux-solaris-and-freebsd-driver-550-54-14-production-branch-release/283925
version="550.54.14" # 20240228

echo "found version: $version"

script_dir=$(dirname "$0")

name="NVIDIA-Linux-x86_64-$version"
filename="$name.run"
outdir="debian"
debdir="$outdir/DEBIAN"

rm -rf $outdir
mkdir -p $outdir
mkdir -p $debdir

dwnedfile="$filename"
if [ ! -f $dwnedfile ]; then
    url="http://download.nvidia.com/XFree86/Linux-x86_64/$version/$filename"
    echo "Downloading Nvidia drivers: $url as file: $dwnedfile"
    cmd="curl $url -o $dwnedfile"
    echo $cmd
    eval $cmd
fi

# validate the file is ok
sh $dwnedfile --check


bindir="$outdir/usr/bin"
mkdir -p $bindir
cp resources/bin/load_nvidia_graphics_driver.sh $bindir/

install_dir="usr/share/pkg-nvidia-driver-ltsb"
rootdir="$outdir/${install_dir}/"
mkdir -p $rootdir
cp $dwnedfile $rootdir
chmod +x $rootdir/$dwnedfile

ctrlfile="$debdir/control"
prefile="$debdir/preinst" 
postfile="$debdir/postinst"

cwd=`pwd`
cd $outdir
find . -type f ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' -printf '%P ' | xargs md5sum > DEBIAN/md5sums
cd $cwd

package="pkg-nvidia-driver-ltsb"
maintainer="Nvidia <https://www.nvidia.com/en-us/support/>"
arch="amd64"
depends="dkms"

#date=`date -u +%Y%m%d`
#echo "date=$date"

#gitrev=`git rev-parse HEAD | cut -b 1-8`
gitrevfull=`git rev-parse HEAD`
gitrevnum=`git log --oneline | wc -l | tr -d ' '`
#echo "gitrev=$gitrev"

buildtimestamp=`date -u +%Y%m%d-%H%M%S`
hostname=`hostname`
echo "build machine=${hostname}"
echo "build time=${buildtimestamp}"
echo "gitrevfull=$gitrevfull"
echo "gitrevnum=$gitrevnum"

debian_revision="${gitrevnum}"
upstream_version="${version}"
echo "upstream_version=$upstream_version"
echo "debian_revision=$debian_revision"

packageversion="${upstream_version}-github${debian_revision}"
packagename="${package}_${packageversion}_${arch}"
echo "packagename=$packagename"
packagefile="${packagename}.deb"
echo "packagefile=$packagefile"

description="build machine=${hostname}, build time=${buildtimestamp}, git revision=${gitrevfull}"
if [ ! -z ${BUILD_NUMBER} ]; then
    echo "build number=${BUILD_NUMBER}"
    description="$description, build number=${BUILD_NUMBER}"
fi

installedsize=`du -s $outdir | awk '{print $1}'`

#for format see: https://www.debian.org/doc/debian-policy/ch-controlfields.html
cat > $ctrlfile << EOF |
Section: restricted/misc
Priority: optional
Maintainer: $maintainer
Version: $packageversion
Package: $package
Architecture: $arch
Pre-Depends: virt-what
Depends: $depends
Installed-Size: $installedsize
Description: NVIDIA display driver from the ltsb (long lived) branch, $description
EOF

echo "Generating preinstall file: $prefile"
cmd="cat ${script_dir}/../resources/preinst > $prefile"
#echo $cmd
eval $cmd
chmod 775 $prefile

echo "Generating postinstall file: $postfile"
cat > $postfile << EOF |
#! /usr/bin/env bash

# running-in-container is part of upstart which is only available on ubuntu 12.04 and 14.04
# virt-what does not support lxd on 12.04
insidelxd="unknown"
if [ -x "\$(command -v running-in-container)" ]; then
    if running-in-container | grep -q lxc; then # lxd container
        insidelxd="true"
    else
        insidelxd="false"
    fi
else
    if [ -x "\$(command -v virt-what)" ]; then
       if [[ \$EUID -ne 0 ]]; then
            echo "virt-what must be run as root"
        else
            if virt-what | grep -q lxc; then # lxd container
                insidelxd="true"
            else
                insidelxd="false"
            fi
        fi
    fi
fi

if [ "\$insidelxd" == "true" ]; then # lxd container
    cmd="/${install_dir}/$filename -a -q -ui=none --no-kernel-module"
else
    cmd="/${install_dir}/$filename -a -q --dkms -ui=none --no-install-compat32-libs"
fi

echo \$cmd
eval \$cmd
EOF
sleep 2
chmod 775 $postfile

echo "Creating .deb file: $packagefile"
rm -f ${package}_*.deb
fakeroot dpkg-deb -Zxz --build $outdir $packagefile

echo "Package info"
dpkg -I $packagefile

echo "Finished"
