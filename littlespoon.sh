#!/bin/bash -e
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

VERSION=0.3
LITTLESPOON=`readlink -f "${0%/*}"`

# Argument defaults
JOB_NAME="littlespoon_$$"
SHARE_NAME="//gagri.garvan.unsw.edu.au/GRIW"
SCRATCH_PATH="/share/Temp/$USER/littlespoon_$$"
CREDS_FILE="~/.gagri.creds"

# The smbclient command
SMBCLIENT_COMMAND="smbclient"

ValidateScratchSpace()
{
	echo "ValidateScratchSpace: TODO"
	# TODO: Free space and permission checks, etc.
}


# Parse the named arguments
while getopts ":s:N:t:A:R:f:F:a:" OPTION; do
	case $OPTION in
		s)	SHARE_NAME=$OPTARG 
			;;
		N)	JOB_NAME=$OPTARG 
			;;
		t)	SCRATCH_PATH=$OPTARG
			;;
		A)	CREDS_FILE=$OPTARG
			;;
		R)	RESULTS_SUBDIR=$OPTARG
			;;
		f)	CIFS_FILE_LIST=$OPTARG
			if [ ! -e "$CIFS_FILE_LIST" ]; then
				echo "$CIFS_FILE_LIST does not exist!"
				exit 1
			fi
			;;
		F)	FILTER_REGEX=$OPTARG
			;;
		a)	COMMAND_ARGUMENTS="$COMMAND_ARGUMENTS $OPTARG"
			;;
		\?)	echo "Unknown option: -$OPTARG" >&2
			exit 1
			;;
		:)	echo "Option -$OPTARG requires an argument." >&2 
			exit 1
			;;
	esac
done

# Parse positional arguments
OPTIND_INC=$((3 + OPTIND))
if [ $# -lt $OPTIND_INC ] || [ $# -lt 4 ]; then
	echo "Usage: bigspoon.sh [-s <CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <creds file>] [-a <argument to command (may be specified multiple times)>]<source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>"
	exit 1
fi

#Start execution
echo "Starting littlespoon version ""$VERSION"

OPT_ARRAY=("$@")
SRC_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND-1:1}
DEST_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND:1}
NUM_CONCURRENT_TASKS=${OPT_ARRAY[@]:$OPTIND+1:1}
COMMAND_ARGS=${OPT_ARRAY[@]:$OPTIND+2:${#OPT_ARRAY[@]}-$OPTIND+1}
COMMAND="${COMMAND_ARGS[*]}"

# Check the scratch space
ValidateScratchSpace

# Work out list of directories we are copying from gagri
if [[ -z "$CIFS_FILE_LIST" ]]; then
	# Get a directory listing on the target directory on gagri
	CIFS_DIR_LISTING=( $($SMBCLIENT_COMMAND -A $CREDS_FILE $SHARE_NAME -D $SRC_CIFS_DIR -c dir 2>/dev/null | awk '{if ($2 == "D" && $1 !~ /\.+/) { print $1 }}') )
else
	# Get the listing from the supplied file
	CIFS_DIR_LISTING=( $(sed -r 's/^\s*//; s/\s*$//; /^$/d' "$CIFS_FILE_LIST") )
fi

# Filter by supplied regex
if [[ ! -z "$FILTER_REGEX" ]];
then
	tmp=( "${CIFS_DIR_LISTING[@]}" )
	CIFS_DIR_LISTING=( $(for i in ${tmp[@]}; do echo "$i"; done | grep -E "$FILTER_REGEX") )
fi

# Check we have >=1 directories to littlespoon
if [ ${#CIFS_DIR_LISTING[@]} -eq 0 ]; then
	echo "ERROR: No directories in final list"
	exit 1
fi

# We now have our final list of directories
echo "Directory listing: ${CIFS_DIR_LISTING[@]}"

# Submit the tasks.  Tasks are structured as follows:
#   1) Fetch job, CIFS --> scratch space.  This may be held on the put job of a previous task.
#   2) Execute job.  In this case, aarsta just wants command to be executed. This is held on the fetch job.
#   3) Put job, scratch --> CIFS.  This is held on the execute job.
#   4) Clean up by rm -r scratch/*

# Export variables for use by grab_a_gag.sh and put_a_gag.sh
export SMBCLIENT="$SMBCLIENT_COMMAND -A $CREDS_FILE $SHARE_NAME"
echo "SMBCLIENT=$SMBCLIENT"

EXEC_DIR=$SCRATCH_PATH

TASK_INDEX=0
for TASK_DIRECTORY in "${CIFS_DIR_LISTING[@]}"; do

	echo "TASK_INDEX=$TASK_INDEX"
	echo "TASK_DIRECTORY=$TASK_DIRECTORY"
	# 1) Fetch job
	# Prepare the scratch space
	echo "  Preparing scratch"
	THIS_SCRATCH_PATH=$SCRATCH_PATH/$TASK_DIRECTORY
	mkdir -p $THIS_SCRATCH_PATH
	rm -rf $THIS_SCRATCH_PATH/* > /dev/null 2>&1
	mkdir -p $THIS_SCRATCH_PATH/input $THIS_SCRATCH_PATH/output
	# Submit the fetch jobs, using Aaron's script
	echo "  Submitting get jobs (ID $JOB_NAME"_F_"$TASK_INDEX)"
	if [ $TASK_INDEX -lt $NUM_CONCURRENT_TASKS ]; then
		echo "    Immediate"
		qsub -q all.q -wd $THIS_SCRATCH_PATH -pe orte 1 -N $JOB_NAME"_F_"$TASK_INDEX -j y -b y -shell n "$LITTLESPOON"/grab_a_gag.sh "$SRC_CIFS_DIR/$TASK_DIRECTORY/*" "$THIS_SCRATCH_PATH"/input
	else
		echo "    Waiting on $JOB_NAME"_C_"$((TASK_INDEX - NUM_CONCURRENT_TASKS))"
		qsub -q all.q -wd $THIS_SCRATCH_PATH -pe orte 1 -N $JOB_NAME"_F_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_C_"$((TASK_INDEX - NUM_CONCURRENT_TASKS)) "$LITTLESPOON"/grab_a_gag.sh "$SRC_CIFS_DIR/$TASK_DIRECTORY/*" "$THIS_SCRATCH_PATH"/input
	fi
	
	# 2) Execute command.  The command is a script. 
	# It is expected that this contains one or more qsub -q all.qs.  The qsub -q all.q jobs 
	# are submitted with names and hold_jids so that the first job to be executed
	# holds waiting for $WAIT_JOB_ID to be completed, and that the last job(s) to be
	# executed have a name of $EXEC_JOB_ID.
	echo "  Submitting compute job $JOB_NAME"_E_"$TASK_INDEX, waiting on $JOB_NAME"_F_"$TASK_INDEX"
	
	cd $THIS_SCRATCH_PATH
	export WAIT_JOB_ID="$JOB_NAME"_F_"$TASK_INDEX"
	export EXEC_JOB_ID="$JOB_NAME"_E_"$TASK_INDEX"
    COMMAND_TO_EXEC="$COMMAND $TASK_DIRECTORY $COMMAND_ARGUMENTS"
	eval $COMMAND_TO_EXEC
	
	# 3) Put job.  It is expected that the output of the job is at 
	# $THIS_SCRATCH_PATH/output and will be put to $DEST_CIFS_DIR/$TASK_DIRECTORY
	echo "  Submitting push job $JOB_NAME"_P_"$TASK_INDEX, waiting on $JOB_NAME"_E_"$TASK_INDEX"
	qsub -q all.q -wd $THIS_SCRATCH_PATH -pe orte 1 -N $JOB_NAME"_P_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_E_"$TASK_INDEX "$LITTLESPOON"/put_a_gag.sh "$THIS_SCRATCH_PATH/output/" "$DEST_CIFS_DIR" "$TASK_DIRECTORY"
	
	# 4) Clean up
	echo "  Submitting cleanup job $JOB_NAME"_C_"$TASK_INDEX, waiting on $JOB_NAME"_P_"$TASK_INDEX"
	qsub -q all.q -wd $SCRATCH_PATH -pe orte 1 -N $JOB_NAME"_C_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_P_"$TASK_INDEX rm -r "$THIS_SCRATCH_PATH"
	
    TASK_INDEX=$[$TASK_INDEX +1]
done

