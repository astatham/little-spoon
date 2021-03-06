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

VERSION=0.10
LITTLESPOON=`readlink -f "${0%/*}"`

# Argument defaults
JOB_NAME="littlespoon_$$"
DEFAULT_SHARE_NAME="//gagri.garvan.unsw.edu.au/GRIW"
SCRATCH_PATH="/share/Temp/$USER/littlespoon_$$"
CREDS_FILE="~/.gagri.creds"
VERBOSE=1

# The smbclient command
SMBCLIENT_COMMAND="smbclient --socket-options=\"TCP_NODELAY IPTOS_LOWDELAY SO_KEEPALIVE SO_RCVBUF=131072 SO_SNDBUF=131072\""

ValidateScratchSpace()
{
	verbose && echo "ValidateScratchSpace: TODO"
	# TODO: Free space and permission checks, etc.
}

function verbose () {
    [[ $VERBOSE -eq 1 ]] && return 0 || return 1
}

# Parse the named arguments
while getopts ":s:d:N:t:A:R:f:F:a:qh1:" OPTION; do
	case $OPTION in
		s)	SOURCE_SHARE_NAME=$OPTARG 
			;;
		d)	DEST_SHARE_NAME=$OPTARG
			;;
		N)	JOB_NAME="$OPTARG"_$$
			;;
		t)	SCRATCH_PATH=$OPTARG"/$USER/littlespoon_$$"
			;;
		A)	CREDS_FILE=$OPTARG
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
		q)	VERBOSE=0
			;;
		h)	echo "Usage: littlespoon.sh [-h] [-q] [-s <source CIFS share>] [-d <destination CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <credentialss file>] [-a <argument to command>] [-1 <single directory] <source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>"
			echo ""
			echo "positional arguments:"
			echo "  <source CIFS directory>      Directory on source CIFS share input data directories are located"
			echo "  <dest CIFS directory>        Directory on destination CIFS share output data is to be placed"
			echo "  <maximum concurrent tasks>   Maximum number of 'command' instances to run simulteneously"
			echo "  <command>                    The script to be executed"
			echo ""
			echo ""
			echo "optional arguments:"
			echo "  -h                           Show this help message and exit"
			echo "  -q                           Quiet mode - the only output will be the SGE jobid of the final queued job"
			echo "  -s <source CIFS share>       Source CIFS share to copy data from; defaults to '//gagri.garvan.unsw.edu.au/GRIW'"
			echo "  -d <destination CIFS share>  Destination CIFS share to copy data to; defaults to '//gagri.garvan.unsw.edu.au/GRIW'"
			echo "  -N <Job name prefix>         Prefix for jobs submitted to SGE; defaults to 'littlespoon_<generated number>'"
			echo "  -t <temp location            Location on the cluster where data will be processed; defaults to '/share/Temp/<username>/littlespoon_<generated number>'"
			echo "  -A <credentialss file>       Location of file containing CIFS login credentials; defaults to '~/.gagri.creds'"
			echo "  -a <argument to command>     Additional argument to be passed to <command>; may be specified multiple times"
			echo "  -1 <single directory>        Only process a specified single directory of data from the <source CIFS directory>"
			exit 0
			;;
		1)	CIFS_DIR_LISTING=$OPTARG
			;;
		\?)	echo "Unknown option: -$OPTARG" >&2
			exit 1
			;;
		:)	echo "Option -$OPTARG requires an argument." >&2 
			exit 1
			;;
	esac
done

# Set share names to default if not specified
if [[ -z $SOURCE_SHARE_NAME ]]; then
	SOURCE_SHARE_NAME=$DEFAULT_SHARE_NAME;
fi

if [[ -z $DEST_SHARE_NAME ]]; then
	DEST_SHARE_NAME=$DEFAULT_SHARE_NAME;
fi

# Parse positional arguments
OPTIND_INC=$((3 + OPTIND))
if [ $# -lt $OPTIND_INC ] || [ $# -lt 4 ]; then
	echo "Usage: littlespoon.sh [-h] [-q] [-s <source CIFS share>] [-d <destination CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <credentialss file>] [-a <argument to command>] [-1 <single directory] <source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>"
	exit 1
fi

#Start execution
verbose && echo "Starting littlespoon version ""$VERSION"

OPT_ARRAY=("$@")
SRC_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND-1:1}
DEST_CIFS_DIR=${OPT_ARRAY[@]:$OPTIND:1}
NUM_CONCURRENT_TASKS=${OPT_ARRAY[@]:$OPTIND+1:1}
COMMAND_ARGS=${OPT_ARRAY[@]:$OPTIND+2:${#OPT_ARRAY[@]}-$OPTIND+1}
COMMAND="${COMMAND_ARGS[*]}"

# Check the scratch space
# ValidateScratchSpace

# Work out list of directories we are copying from gagri

if [[ -z "$CIFS_FILE_LIST" ]]; then
	if [[ -z "$CIFS_DIR_LISTING" ]]; then
		# Get a directory listing on the target directory on gagri
		CIFS_CMD="$SMBCLIENT_COMMAND -A $CREDS_FILE $SOURCE_SHARE_NAME -D $SRC_CIFS_DIR -c dir 2>/dev/null"
		CIFS_DIR_LISTING=( `eval $CIFS_CMD | awk '{if ($2 == "D" && $1 !~ /\.+/) { print $1 }}'` )
	fi
else
	# Get the listing from the supplied file
	CIFS_DIR_LISTING=( $(sed -r 's/^\s*//; s/\s*$//; /^$/d' "$CIFS_FILE_LIST") )
fi

# Filter by supplied regex
if [[ ! -z "$FILTER_REGEX" ]];
then
	tmp=( "${CIFS_DIR_LISTING[@]}" )
	CIFS_DIR_LISTING=( $(for i in ${tmp[@]}; do verbose && echo "$i"; done | grep -E "$FILTER_REGEX") )
fi

# Check we have >=1 directories to littlespoon
if [ ${#CIFS_DIR_LISTING[@]} -eq 0 ]; then
	echo "ERROR: No directories in final list"
	exit 1
fi

# We now have our final list of directories
verbose && echo "Directory listing: ${CIFS_DIR_LISTING[@]}"

# Submit the tasks.  Tasks are structured as follows:
#   1) Fetch job, CIFS --> scratch space.  This may be held on the put job of a previous task.
#   2) Execute job.  In this case, aarsta just wants command to be executed. This is held on the fetch job.
#   3) Put job, scratch --> CIFS.  This is held on the execute job.
#   4) Clean up by rm -r scratch/*

# Export variables for use by grab_a_gag.sh and put_a_gag.sh
SMBCLIENT_FETCH="$SMBCLIENT_COMMAND -A $CREDS_FILE $SOURCE_SHARE_NAME"
SMBCLIENT_PUSH="$SMBCLIENT_COMMAND -A $CREDS_FILE $DEST_SHARE_NAME"
verbose && echo "SMBCLIENT_FETCH=$SMBCLIENT_FETCH, SMBCLIENT_PUSH=$SMBCLIENT_PUSH"

EXEC_DIR=$SCRATCH_PATH

TASK_INDEX=0
for TASK_DIRECTORY in "${CIFS_DIR_LISTING[@]}"; do

	verbose && echo "TASK_INDEX=$TASK_INDEX"
	verbose && echo "TASK_DIRECTORY=$TASK_DIRECTORY"
	# 1) Fetch job
	# Prepare the scratch space
	verbose && echo "  Preparing scratch"
	THIS_SCRATCH_PATH=$SCRATCH_PATH/$TASK_DIRECTORY
	mkdir -p $THIS_SCRATCH_PATH
	rm -rf $THIS_SCRATCH_PATH/* > /dev/null 2>&1
	mkdir -p $THIS_SCRATCH_PATH/input $THIS_SCRATCH_PATH/output
	# Submit the fetch jobs, using Aaron's script
	verbose && echo "  Submitting get jobs (ID $JOB_NAME"_F_"$TASK_INDEX)"
	if [ $TASK_INDEX -lt $NUM_CONCURRENT_TASKS ]; then
		verbose && echo "    Immediate"
		qsub -q all.q -wd $THIS_SCRATCH_PATH -v SMBCLIENT="$SMBCLIENT_FETCH" -N $JOB_NAME"_F_"$TASK_INDEX -j y -b y -shell n "$LITTLESPOON"/grab_a_gag.sh "$SRC_CIFS_DIR/$TASK_DIRECTORY/*" "$THIS_SCRATCH_PATH"/input > /dev/null
	else
		verbose && echo "    Waiting on $JOB_NAME"_C_"$((TASK_INDEX - NUM_CONCURRENT_TASKS))"
		qsub -q all.q -wd $THIS_SCRATCH_PATH -v SMBCLIENT="$SMBCLIENT_FETCH" -N $JOB_NAME"_F_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_C_"$((TASK_INDEX - NUM_CONCURRENT_TASKS)) "$LITTLESPOON"/grab_a_gag.sh "$SRC_CIFS_DIR/$TASK_DIRECTORY/*" "$THIS_SCRATCH_PATH"/input > /dev/null
	fi
	
	# 2) Execute command.  The command is a script. 
	# It is expected that this contains one or more qsub -q all.qs.  The qsub -q all.q jobs 
	# are submitted with names and hold_jids so that the first job to be executed
	# holds waiting for $WAIT_JOB_ID to be completed, and that the last job(s) to be
	# executed have a name of $EXEC_JOB_ID.
	verbose && echo "  Submitting compute job $JOB_NAME"_E_"$TASK_INDEX, waiting on $JOB_NAME"_F_"$TASK_INDEX"
	
	cd $THIS_SCRATCH_PATH
	export WAIT_JOB_ID="$JOB_NAME"_F_"$TASK_INDEX"
	export EXEC_JOB_ID="$JOB_NAME"_E_"$TASK_INDEX"
        COMMAND_TO_EXEC="$COMMAND $TASK_DIRECTORY $COMMAND_ARGUMENTS > /dev/null"
	eval $COMMAND_TO_EXEC
	
	# 3) Put job.  It is expected that the output of the job is at 
	# $THIS_SCRATCH_PATH/output and will be put to $DEST_CIFS_DIR/$TASK_DIRECTORY
	verbose && echo "  Submitting push job $JOB_NAME"_P_"$TASK_INDEX, waiting on $JOB_NAME"_E_"$TASK_INDEX"
	qsub -q all.q -wd $THIS_SCRATCH_PATH -v SMBCLIENT="$SMBCLIENT_PUSH" -N $JOB_NAME"_P_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_E_"$TASK_INDEX "$LITTLESPOON"/put_a_gag.sh "$THIS_SCRATCH_PATH/output/" "$DEST_CIFS_DIR" "$TASK_DIRECTORY" > /dev/null
	
	# 4) Clean up
	verbose && echo "  Submitting cleanup job $JOB_NAME"_C_"$TASK_INDEX, waiting on $JOB_NAME"_P_"$TASK_INDEX"
	JOBID=`qsub -q all.q -wd $SCRATCH_PATH -N $JOB_NAME"_C_"$TASK_INDEX -j y -b y -shell n -hold_jid $JOB_NAME"_P_"$TASK_INDEX rm -r "$THIS_SCRATCH_PATH" | cut -d " " -f3`
	
    TASK_INDEX=$[$TASK_INDEX +1]
done

verbose && echo "All jobs submitted" || echo $JOBID
