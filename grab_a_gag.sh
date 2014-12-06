#!/bin/bash -e
#grab_a_gag.sh <file/directory name> [target directory ./ default]

#Default server and credentials, unless already set
if [[ -z "$SMBCLIENT" ]]; then
	SMBCLIENT="smbclient --socket-options=\"TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE SO_RCVBUF=131072 SO_SNDBUF=131072\" //Gagri/GRIW -A ~/.smbclient"
fi

case "$#" in
1)  DESTDIR="./";;
2)  DESTDIR="$2";;
*)  echo "Usage:  $(basename $0) {Remote file/directory} [Local target directory]"
    exit 1;;
esac

#Check if DESTDIR exists
if [ ! -d "$DESTDIR" ]
then
    echo "$DESTDIR is not a valid local path"
    exit 1
fi

CURDIR=$(pwd)
#Go to target directory and download the target
cd "$DESTDIR"
TARGET="${1%/}" # remove trailing slash in case a directory is the target
fn="${TARGET##*/}" # filename
dn="${TARGET%/*}"  # dirname

CMD="${SMBCLIENT} -c \"prompt; recurse; cd ${dn}; mget ${fn}\""
echo $CMD
eval $CMD
cd "$CURDIR"
