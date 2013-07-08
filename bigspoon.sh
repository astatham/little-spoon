#!/bin/bash
#
# bigspoon.sh -- Execute a given command in parallel on data stored on a CIFS share.
#
# The bulk of Garvan data are stored on CIFS shares, but this is not accessible to
# the Wolfpack compute cluster.  The spoon scripts simplify the running of commands
# on data stored on Gagri, by automatically copying the data from Gagri, running
# the user-supplied commands on the Wolfpack cluster, then copying the data back.
#
# bigspoon is the launch point for these scripts, and should be the only one needed
# by users.  bigspoon examines the supplied CIFS directory, and runs littlespoon on
# each subdirectory found.  For each invocation, littlespoon copies all files in its
# subdirectory to scratch space, executes the supplied command, and then copies the
# results back.  This is all performed in parallel on Wolfpack.
#
# Usage:
# bigspoon [-s <CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <creds file>] <source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>
#


# Argument defaults
JOB_NAME='bigspoon'
SHARE_NAME="//gagri.garvan.unsw.edu.au/GRIW"
SCRATCH_PATH="/share/Temp/$USER"
CREDS_FILE="~/.gagri.creds"

# The smbclient command
SMBCLIENT_COMMAND="smbclient"
QSUB_COMMAND="qsub"

EXEC_DIR=$PWD


ValidateScratchSpace()
{
	echo "ValidateScratchSpace: TODO"
	# TODO: Free space and permission checks, etc.
}


# Parse the named arguments
while getopts ":s:N:t:A:" OPTION; do
	case $OPTION in
		s)	SHARE_NAME=$OPTARG 
			;;
		N)	JOB_NAME=$OPTARG 
			;;
		t)	SCRATCH_PATH=$OPTARG
			;;
		A)	CREDS_FILE=$OPTARG
			;;
		\?)	echo "Unknown option: -$OPTARG" >&2 
			;;
		:)	echo "Option -$OPTARG requires an argument." >&2 
			;;
	esac
done

# Parse positional arguments
OPTIND_INC=$((3 + OPTIND))
if [ $# -lt $OPTIND_INC ] || [ $# -lt 4 ]; then
	echo "Usage: bigspoon.sh [-s <CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <creds file>] <source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>"
	exit 1
fi

OPT_ARRAY=("$@")
SRC_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND-1:1}
DEST_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND:1}
NUM_CONCURRENT_TASKS=${OPT_ARRAY[@]:$OPTIND+1:1}
COMMAND_ARGS=${OPT_ARRAY[@]:$OPTIND+2:${#OPT_ARRAY[@]}-$OPTIND+1}
COMMAND="${COMMAND_ARGS[*]}"

# Check the scratch space
ValidateScratchSpace $SCRATCH_PATH

# Get a directory listing on the target directory on gagri
CIFS_DIR_LISTING=( $($SMBCLIENT_COMMAND -A $CREDS_FILE $SHARE_NAME -D $SRC_CIFS_DIR -c dir 2>/dev/null | awk '{if ($2 == "D" && $1 !~ /\.+/) { print $1 }}') )

# Prepare the scratch space
mkdir -p $SCRATCH_PATH
cd $SCRATCH_PATH

# Submit the littlespoon jobs
TASK_INDEX=0
for TASK_DIRECTORY in "${CIFS_DIR_LISTING[@]}"; do
	if [ $TASK_INDEX -lt $NUM_CONCURRENT_TASKS ]; then
		qsub -pe orte 1 -N $JOB_NAME"_"$TASK_INDEX -cwd -v CREDS_FILE=\'$CREDS_FILE\',SHARE_NAME=\'$SHARE_NAME\',SOURCE_DIR=\'$SRC_CIFS_DIR\',DEST_DIR=\'$DEST_CIFS_DIR\',SCRATCH=\'$SCRATCH_PATH\',COMMAND=\'$COMMAND\' littlespoon.sh
	else
		qsub -pe orte 1 -N $JOB_NAME"_"$TASK_INDEX -cwd -v CREDS_FILE=\'$CREDS_FILE\',SHARE_NAME=\'$SHARE_NAME\',SOURCE_DIR=\'$SRC_CIFS_DIR\',DEST_DIR=\'$DEST_CIFS_DIR\',SCRATCH=\'$SCRATCH_PATH\',COMMAND=\'$COMMAND\' -hold_jid $JOB_NAME"_"$((TASK_INDEX - NUM_CONCURRENT_TASKS)) littlespoon.sh
	fi
	(( TASK_INDEX++ ))
done

