#!/bin/bash -e
#put_a_gag.sh <Local directory> <Remote target directory> <Success indicator file name>

#Default server and credentials, unless already set
if [[ -z "$SMBCLIENT" ]]; then
	SMBCLIENT="smbclient //Gagri/GRIW -A ~/.smbclient"
fi

if [ $# -ne 3 ]
then
  echo "Usage: $(basename $0) {Local directory} {Remote target directory} {Success indicator file name}"
  exit 1
fi

# Recursively create directories up to the target.  Currently a bit stupid,
# trying to create directories regardless of whether they already exist or not, 
# so expect a lot of collision errors, which can be ignored.  Requires that the 
# paths use the DOS/CIFS delimiter "\", not the POSIX "/".
PATH_HEAD=""
PATH_TAIL="${2}"
while [ $PATH_TAIL != ""]; do
	PATH_HEAD=${PATH_HEAD}"\\"${PATH_TAIL%%\\.*}
	PATH_TAIL=${PATH_TAIL#\\.*}
	${SMBCLIENT} -D "${PATH_HEAD}" -c "mkdir ${PATH_TAIL}"
done

# Verify that the target directory is available, else bail.
${SMBCLIENT} -c "cd ${2}"
if [ $? -ne 0 ]; then
	echo "Could not create target directory ${2} on CIFS server."
	exit 2
fi

# Perform the copy
CURDIR=$(pwd)
cd $1
${SMBCLIENT} -D "${2}" -c "prompt; recurse; mput *"
if [ $? -ne 0 ]; then
	echo "Error copying files to CIFS server."
	cd $CURDIR
	exit 3
fi
cd $CURDIR

# Touch a success indicator file, for later use by the cleanup code.  If this
# isn't present, then the cleanup code shouldn't execute.
touch ${3}
