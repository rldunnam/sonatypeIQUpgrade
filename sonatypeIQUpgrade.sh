#!/bin/bash  

#usage
# /iqupgradev2.sh -v 191

#default value
VER="latest"

#Set arguement for -v version variable
while getopts "v:" opt; do
	case $opt in
		v) VER="$OPTARG" ;;
		*) echo "Usage: $0 [-v version]" && exit 1 ;;
	esac
done

#set var 
URL=https://download.sonatype.com/clm/server/nexus-iq-server-1."${VER}".0-01-bundle.tar.gz  
WORKDIR=/opt/nexus-iq-server 
ARCHIVEDIR=/opt/nexus-iq-server/Archive 

#Stop service 
systemctl stop nexusiq.service  

#archive clean up 
rm -rf $ARCHIVEDIR/* 

#archive current file 
mv $WORKDIR/nexus-iq-server-1.* $ARCHIVEDIR/ 

#download .tar 
cd $WORKDIR 
wget $URL 

#unpack tar 
tar -xzf nexus-iq-server*.tar.gz --wildcards nexus-iq-server*.jar 
rm nexus-iq-server*.tar.gz

#change ownership of .jar 
chown nexus:users nexus-iq-server*.* 

#start service 
systemctl start nexusiq.service  
