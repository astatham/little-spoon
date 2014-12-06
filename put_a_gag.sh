#!/bin/bash -e
#put_a_gag.sh <file/directory name> [target directory]

#Default server and credentials, unless already set
if [[ -z "$SMBCLIENT" ]]; then
	SMBCLIENT="smbclient --socket-options=\"TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE SO_RCVBUF=131072 SO_SNDBUF=131072\" //Gagri/GRIW -A ~/.smbclient"
fi

if [ $# -ne 3 ]
then
  echo "Usage: $(basename $0) {Local directory} {Remote target directory} {New directory name}"
  exit 1
fi

##Check if $1 exists
#if [ ! -e "$1" ]
#then
#    echo "$1 does not exist"
#    exit 1
#fi
CURDIR=$(pwd)

#Copy logs into $1
cp littlespoon*.o* littlespoon*.e* $1 2> /dev/null || :

cd $1
CMD="${SMBCLIENT} -c \"cd ${2}; mkdir ${3}; cd ${3}; prompt; recurse; mput *\""
echo $CMD
eval $CMD
cd $CURDIR

