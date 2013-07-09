#!/bin/bash -e
#grab_a_gag.sh <file/directory name> [target directory ./ default]

#Default server and credentials, unless already set
if [[ -z "$SMBCLIENT" ]]; then
	SMBCLIENT="smbclient //Gagri/GRIW -A ~/.smbclient"
fi

if [ $# -ne 2 ]
then
  echo "Usage: $(basename $0) {Local file/directory} {Remote target directory}"
  exit 1
fi

#Check if $1 exists
if [ ! -e "$1" ]
then
    echo "$1 does not exist"
    exit 1
fi

CMD="${SMBCLIENT} -c \"prompt; recurse; cd ${2}; mput ${1}\""
eval $CMD

