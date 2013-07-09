#!/bin/bash

./littlespoon.sh -A ~/garvan.creds -s //gagri.garvan.unsw.edu.au/GRIW -N testJob -t /share/Temp/marpin/spoontest -R results /ICGCPancreas/MarkP/temp/spoontest_data /ICGCPancreas/MarkP/temp/spoontest_result_script 3 test_runscript.sh

#./littlespoon.sh -A ~/garvan.creds -s //gagri.garvan.unsw.edu.au/GRIW -N testJob -t /share/Temp/marpin/spoontest -R results /ICGCPancreas/MarkP/temp/spoontest_data /ICGCPancreas/MarkP/temp/spoontest_result_qsub 3 qsub -pe orte 1 -b y -shell y 'mkdir output; ls -lah > output/listing.txt'

