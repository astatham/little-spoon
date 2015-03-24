#!/bin/bash
#grab_a_gag.sh <file/directory name> [target directory ./ default]

#Default server and credentials, unless already set
if [[ -z "$SMBCLIENT" ]]; then
	SMBCLIENT="smbclient --socket-options=\"TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE SO_RCVBUF=131072 SO_SNDBUF=131072\" //Gagri/GRIW -A ~/.smbclient"
fi

case "$#" in
1)  DESTDIR="$PWD";;
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
TARGET="${1%/}" # remove trailing slash in case a directory is the target
fn="${TARGET##*/}" # filename
dn="${TARGET%/*}"  # dirname

CMD="${SMBCLIENT} -c \"prompt; recurse; cd ${dn}; mget ${fn}\""
echo $CMD

# Download to temporary directory
DOWNLOAD_DIR=/tmp/littlespoon_"$$"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

ATTEMPTS=1
eval $CMD 2>&1 | tee smbclient.log
! grep -qE "NT_STATUS_IO_TIMEOUT|NT_STATUS_PIPE_BROKEN" smbclient.log
while [ $? -ne 0 ]
do
    echo "Transfer disrupted, retrying in 10 seconds..."
    sleep 10
	((ATTEMPTS++))
	rm -rf "$dn"
	eval $CMD 2>&1 | tee smbclient.log
	! grep -qE "NT_STATUS_IO_TIMEOUT|NT_STATUS_PIPE_BROKEN" smbclient.log
done
rm -f smbclient.log
mv "$fn" $DESTDIR

echo "Transfer completed in" $ATTEMPTS "attempt(s)"

cd "$CURDIR"
rm -rf "$DOWNLOAD_DIR"