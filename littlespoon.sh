#!/bin/bash
#
# littlespoon.sh -- Execute a given command in parallel on data stored on a CIFS share.
#
# The bulk of Garvan data are stored on CIFS shares, but this is not accessible to
# the Wolfpack compute cluster.  The spoon scripts simplify the running of commands
# on data stored on Gagri, by automatically copying the data from Gagri, running
# the user-supplied commands on the Wolfpack cluster, then copying the data back.
#
# littlespoon examines the supplied CIFS directory, and performs the following on
# each subdirectory found:
#   1) copies all files in the subdirectory to scratch space
#   2) executes the supplied command
#   3) copies the results back to gagri.
# This is all performed in parallel on Wolfpack.
#
# Usage:
# littlespoon [-s <CIFS share>] [-N <Job name prefix>] [-t <temp location>] 
#	[-A <creds file>] [-R <results subdirectory>] <source CIFS directory> 
#	<dest CIFS directory> <maximum concurrent tasks> <command>
#


# Argument defaults
JOB_NAME='bigspoon'
SHARE_NAME="//gagri.garvan.unsw.edu.au/GRIW"
SCRATCH_PATH="/share/Temp/$USER"
CREDS_FILE="~/.gagri.creds"
RESULTS_SUBDIR="output"

# The smbclient command
SMBCLIENT_COMMAND="smbclient"
QSUB_COMMAND="qsub"

EXEC_DIR=$PWD


ValidateCommand()
{
	echo "ValidateCommand: TODO"
	# TODO: Make sure that $COMMAND is a valid qsub submission
	# Additionally, it:
	#   * Should NOT have a name (-N option)
	#   * Should NOT have any holds (-hold* option)
}

ValidateScratchSpace()
{
	echo "ValidateScratchSpace: TODO"
	# TODO: Free space and permission checks, etc.
}


# Parse the named arguments
while getopts ":s:N:t:A:R:" OPTION; do
	case $OPTION in
		s)	SHARE_NAME=$OPTARG 
			;;
		N)	JOB_NAME=$OPTARG 
			;;
		t)	SCRATCH_PATH=$OPTARG
			;;
		A)	CREDS_FILE=$OPTARG
			;;
		R)  RESULTS_SUBDIR=$OPTARG
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

# Check the command -- it must be a valid qsub submission command
ValidateCommand

# Check the scratch space
ValidateScratchSpace

# Get a directory listing on the target directory on gagri
CIFS_DIR_LISTING=( $($SMBCLIENT_COMMAND -A $CREDS_FILE $SHARE_NAME -D $SRC_CIFS_DIR -c dir 2>/dev/null | awk '{if ($2 == "D" && $1 !~ /\.+/) { print $1 }}') )

# Submit the tasks.  Tasks are structured as follows:
#   1) Fetch job, CIFS --> scratch space.  This may be held on the put job of a previous task.
#   2) Execute job.  In this case, aarsta just wants command to be executed, assuming it's a qsub command.  This is held on the fetch job.
#   3) Put job, scratch --> CIFS.  This is held on the execute job.
TASK_INDEX=0
for TASK_DIRECTORY in "${CIFS_DIR_LISTING[@]}"; do

	# 1) Fetch job
	# Prepare the scratch space
	THIS_SCRATCH_PATH=$SCRATCH_PATH/$TASK_DIRECTORY
	mkdir -p $THIS_SCRATCH_PATH
	rm $THIS_SCRATCH_PATH/*
	
	# Submit the jobs, using Aaron's script
	if [ $TASK_INDEX -lt $NUM_CONCURRENT_TASKS ]; then
		qsub -pe orte 1 -N $JOB_NAME"_F_"$TASK_INDEX -b y -shell n grab_a_gag.sh "$SHARE_NAME/$SRC_CIFS_DIR/$TASK_DIRECTORY/*" $THIS_SCRATCH_PATH
	else
		qsub -pe orte 1 -N $JOB_NAME"_F_"$TASK_INDEX -b y -shell n -hold_jid $JOB_NAME"_P_"$((TASK_INDEX - NUM_CONCURRENT_TASKS)) grab_a_gag.sh "$SHARE_NAME/$SRC_CIFS_DIR/$TASK_DIRECTORY/*" $THIS_SCRATCH_PATH
	fi
	
	# 2) Execute command.  The command at this point is expected to be a qsub command.
	# We need to modify it to add a hold_jid option.
	COMMAND_MOD=${COMMAND/qsub /qsub -hold_jid $JOB_NAME"_F_"$TASK_INDEX -N $JOB_NAME"_E_"$TASK_INDEX }
	eval $COMMAND_MOD
	
	# 3) Put job.  It is expected that the output of the job is at 
	# $SCRATCH_PATH/$TASK_DIRECTORY/$RESULTS_SUBDIR
	qsub -pr orte 1 -N $JOB_NAME"_P_"$TASK_INDEX -b y -shell n -hold_jid $JOB_NAME"_E_"$TASK_INDEX put_a_gag.sh "$THIS_SCRATCH_PATH/$RESULTS_SUBDIR/*" $SHARE_NAME/$DEST_CIFS_DIR/$TASK_DIRECTORY
	
	(( TASK_INDEX++ ))
done

