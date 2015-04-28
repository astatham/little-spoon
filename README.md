littlespoon
============

Giving your cluster little spoonfuls of data at a time so it doesn't gag

Motivation
---

The Garvan cluster 'Wolfpack' cannot directly access our large data stores (gagri/diverse/rhino), and has only a limited amount of usable scratch space for data processing. When running bioinformatic pipelines on many samples, these limitations necessitate the user to copy subsets of data manually from storage for processing and then the results back to storage so as to not run out of space. *littlespoon.sh* was written to automate this process, leveraging the SGE scheduler.

Design
---

The four mandatory arguments to *littlespoon.sh* are the **source** of data to be processed, the **destination** to put processed data, the number of tasks to run simultaneously and the **command** to be executed. *littlespoon.sh* operates on a **directory** basis - where each directory within the **source** has four jobs queued via SGE, each dependent upon the previous completing before starting:

1. A directory is copied from the **source** to the cluster (the *fetch* job)
    * This data is copied to the specified scratch space, and placed in an "input" directory
2. The **command** is executed - performing some sort of processing upon that directory (the *execute* job)
    * This **command** must take it's date input from the "input" folder and place any results to be kept into a separate "output" directory
3. The "output" is copied back from the cluster to the **destination** (the *push* job)
4. The temporary input and output data is deleted from the cluster scratch space (the *clean* job)


Usage
---


    Usage: littlespoon.sh [-h] [-q] [-s <source CIFS share>] [-d <destination CIFS share>] [-N <Job name prefix>] [-t <temp location>] [-A <credentialss file>] [-a <argument to command>] [-1 <single directory] <source CIFS directory> <dest CIFS directory> <maximum concurrent tasks> <command>

    positional arguments:
      <source CIFS directory>      Directory on source CIFS share input data directories are located
      <dest CIFS directory>        Directory on destination CIFS share output data is to be placed
      <maximum concurrent tasks>   Maximum number of 'command' instances to run simulteneously
      <command>                    The script to be executed


    optional arguments:
      -h                           Show this help message and exit
      -q                           Quiet mode - the only output will be the SGE jobid of the final queued job
      -s <source CIFS share>       Source CIFS share to copy data from; defaults to '//gagri.garvan.unsw.edu.au/GRIW'
      -d <destination CIFS share>  Destination CIFS share to copy data to; defaults to '//gagri.garvan.unsw.edu.au/GRIW'
      -N <Job name prefix>         Prefix for jobs submitted to SGE; defaults to 'littlespoon_<generated number>'
      -t <temp location>           Location on the cluster where data will be processed; defaults to '/share/Temp/<username>/littlespoon_<generated number>'
      -A <credentialss file>       Location of file containing CIFS login credentials; defaults to '~/.gagri.creds'
      -a <argument to command>     Additional argument to be passed to <command>; may be specified multiple times
      -1 <single directory>        Only process a specified single directory of data from the <source CIFS directory>
