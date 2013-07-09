#!/bin/bash
mkdir output
qsub -cwd -pe orte 1 -hold_jid $WAIT_JOB_ID -N $EXEC_JOB_ID -b y -shell y ls -lah > output/listing.txt
