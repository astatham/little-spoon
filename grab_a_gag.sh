#!/bin/bash -e
#grab_a_gag.sh <file/directory name> [target directory ./ default]

#Default server and credentials
SMBCLIENT="smbclient //Gagri/GRIW -A ~/.smbclient"

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
eval $CMD
cd "$CURDIR"

