#!/bin/bash

# Test schedulers with iozone
# Fixed: Add support for HP RAID devices
# Fixed: Drop caches before each test run

if [ "$EUID" -ne "0" ]; then echo "Needs su, exiting"; exit 1; fi

unset ARGS;ARGS=$#
if [ ! $ARGS -lt "5" ]; then
    DEV=$1
    DIR=`echo $2 | sed 's//$//g'` # Remove trailing slashes from path
    OUTPUTDIR=`echo $4 | sed 's//$//g'` # Remove trailing slashes from path

    # Create the log file directory if it doesn't exist
    if [ ! -d "$OUTPUTDIR" ]; then mkdir -p $OUTPUTDIR;fi

    # Check the test directory
    if [ ! -d "$DIR" ]; then
        echo "Error: Is $DIR a directory?"
        exit 1
    fi

    # Check the device name
    MDDEV="md*"
    HPDEV="c?d?"
    case "$DEV" in
        $HPDEV ) # HP RAID
            unset SYSDEV;SYSDEV="/sys/block/cciss!$DEV/queue/scheduler"
            unset MD;declare -i MD;MD=0
        ;;
        $MDDEV ) # mdadm RAID
            echo "Found a Linux MD device, checking for schedulers..."
            unset MD;declare -i MD;MD=1
            unset SYSDEV
            SYSDEV=$(mdadm -D /dev/md0 | grep active | awk -F '/' '{print $3}' | sed 's/[0-9]//g')
        ;;
        * )
            unset SYSDEV;SYSDEV="/sys/block/$DEV/queue/scheduler"
            unset MD;declare -i MD;MD=0
        ;;
    esac

    # Check for the output log
    unset OUTPUTLOG;OUTPUTLOG="$OUTPUTDIR/iozone-$DEV-all-results.log"
    if [ -e "$OUTPUTLOG" ]; then echo "$OUTPUTLOG exists, aborting"; exit 1;fi

    # Find available schedulers
    if [ $MD -eq 0 ]; then
        echo "not md device"
        declare -a SCHEDULERS
        SCHEDULERS=`cat $SYSDEV | sed 's/[//g' | sed 's/]//g'`
    else
        declare -a SCHEDULERS; unset MDMEMBER
        for MDMEMBER in ${SYSDEV[@]}; do
            unset SYSDEVMD;SYSDEVMD="/sys/block/"$MDMEMBER"/queue/scheduler"
        done
        SCHEDULERS=`cat $SYSDEVMD | sed 's/[//g' | sed 's/]//g'`
    fi
    if [ -z "$SCHEDULERS" ]; then
        echo "No schedulers found! Wrong device specified? Tried looking in $SYSDEV"
        exit 1
    else
        echo "Schedulers found under $DEV: "$SCHEDULERS
        SIZE=$(($3*1024)) # Size is now MB per thread
        unset RUNS; declare -i RUNS;RUNS=$5
    fi

    # Set record size
    if [ -z "$6" ]; then
        echo "Using the default record size of 16MiB"
        RECORDSIZE="16384" # Set default to 16MB
    else
        RECORDSIZE=$6"m"
    fi

    # Set no. threads
    if [ -z "$7" ]; then
        echo "Testing with 1, 2 "amp; 3 threads (default)"
        THREADS=3
    else
        THREADS=$7
    fi

    SHELL=`which bash`
else
    echo "# Usage:"
    echo "`basename $0`     <#runs> 
"
    echo "time `basename $0` sda /mnt 20480 /dev/shm/server1 3 16 3"
    echo "# The above command will test sda with 1, 2 " 3 threads 3 times per scheduler with 20GiB of data using"
    echo "# 16MiB record size and save logs in /dev/shm/server1/ ."
    echo "# If the record size is omitted the default of 16MiB will be used. (should be buffer size of device)"
    echo "# For HP RAID controllers use device name format c0d0 or c1d2 etc."
    exit 1
fi

function createOutputLog () {
    unset FILE
    echo -e "TesttThroughput (KB/s)tI/O SchedulertThreadstn" > $OUTPUTLOG
    for FILE in $OUTPUTDIR/$DEV*.txt; do
        # results
        unset WRITE;unset REWRITE; unset RREAD; unset MIXED; unset RWRITE
        # Scheduler, threads, iteration
        unset SCHED;unset T; unset I;unset IT
        SCHED=`echo "$FILE" | awk -F'-' '{print $2}'`
        T=`echo "$FILE" | awk -F'-' '{print $3}' | sed 's/t//g'`
        # FIXME, it's ugly
        IT=`echo "$FILE" | awk -F'-' '{print $4}'`
        I=`expr ${IT:1:1}`

        # Get values
        WRITE=`grep "  Initial write " $FILE | awk '{print $5}'`
        REWRITE=`grep "        Rewrite " $FILE | awk '{print $4}'`
        RREAD=`grep "    Random read " $FILE | awk '{print $5}'`
        MIXED=`grep " Mixed workload " $FILE | awk '{print $5}'`
        RWRITE=`grep "   Random write " $FILE | awk '{print $5}'`
        # echo "iwrite $WRITE rwrite $REWRITE rread $RREAD mixed $MIXED random $RWRITE"

        # Print to the file
        if [ -z "$WRITE" -o -z "$REWRITE" -o -z "$RREAD" -o -z "$MIXED" -o -z "$RWRITE" ]; then
            # Something's wrong with our input file, or bug in script
            echo "BUG, unable to parse result:"
            echo "write $WRITE rewrite $REWRITE random read $RREAD mixed $MIXED random write $RWRITE"
            exit 1
        else
            echo -e "Initial writet$WRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Rewritet$RWRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Random readt$RREADt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Mixed workloadt$MIXEDt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Random writet$RWRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
        fi
    done
}

unset ITERATIONS; declare -i ITERATIONS; ITERATIONS=0
unset CURRENTTHREADS; declare -i CURRENTTHREADS
unset IOZONECMD

cd "$DIR"
echo "Using iozone at `which iozone`"

until [ "$ITERATIONS" -ge "$RUNS" ]; do
    let ITERATIONS=$ITERATIONS+1
    for SCHEDULER in $SCHEDULERS; do
        # Change the scheduler
        if [ $MD -eq 1 ]; then
            unset MEMBER
            for MEMBER in $SYSDEV; do
                echo $SCHEDULER > /sys/block/$MEMBER/queue/scheduler
            done
        else
            echo $SCHEDULER > $SYSDEV
        fi
        CURRENTTHREADS=1
        # Repeat until we've tested with all requested threads
        until [ $CURRENTTHREADS -gt $THREADS ]; do
            unset IOZONECMDAPPEND
            IOZONECMDAPPEND="$OUTPUTDIR/$DEV-$SCHEDULER-t$CURRENTTHREADS-i$ITERATIONS.txt"
            #echo "iozonecmdappend is $IOZONECMDAPPEND"
            # Append all test files to the command line (threads/processes)
            unset I; unset IOZONECMD_FILES
            for I in `seq 1 $CURRENTTHREADS`; do
                IOZONECMD_FILES="$IOZONECMD_FILES$DIR/iozone-temp-$I "
            done
            # Drop caches
            echo 3 > /proc/sys/vm/drop_caches
            echo "Testing $SCHEDULER with $CURRENTTHREADS thread(s), run #$ITERATIONS"
            IOZONECMD="iozone -R -i 0 -i 2 -i 8 -s $SIZE -r $RECORDSIZE -b $OUTPUTDIR/$DEV-$SCHEDULER-t$CURRENTTHREADS-i$ITERATIONS.xls -l 1 -u $CURRENTTHREADS -F $IOZONECMD_FILES"
            # Run the command
            echo time $IOZONECMD
            time $IOZONECMD | tee -a $IOZONECMDAPPEND
            # Done testing $CURRENTTHREADS threads/processes, increase to test one more in the loop (if applicable)
            let CURRENTTHREADS=$CURRENTTHREADS+1
        done
    done
    echo "Run #$ITERATIONS done" | tee -a $IOZONECMDAPPEND
done

echo
createOutputLog
echo "Done, logs saved in $OUTPUTDIR"
exit 0
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
29
30
31
32
33
34
35
36
37
38
39
40
41
42
43
44
45
46
47
48
49
50
51
52
53
54
55
56
57
58
59
60
61
62
63
64
65
66
67
68
69
70
71
72
73
74
75
76
77
78
79
80
81
82
83
84
85
86
87
88
89
90
91
92
93
94
95
96
97
98
99
100
101
102
103
104
105
106
107
108
109
110
111
112
113
114
115
116
117
118
119
120
121
122
123
124
125
126
127
128
129
130
131
132
133
134
135
136
137
138
139
140
141
142
143
144
145
146
147
148
149
150
151
152
153
154
155
156
157
158
159
160
161
162
163
164
165
166
167
168
169
170
171
172
173
174
175
176
177
178
179
180
181
182
183
184
185
186
187
188
189
190
191
#!/bin/bash
 
# Test schedulers with iozone
# See https://bbs.archlinux.org/viewtopic.php?pid=969117
# by fackamato, Aug 1, 2011
# changelog:
# 03082011
# Added: Support for Linux MD devices
# Added/fixed: take no. of threads as argument and test accordingly (big rewrite)
# 02082011
# Added: Should now output to a file with the syntax requested by graysky
# Fixed: Add support for HP RAID devices
# Fixed: Drop caches before each test run
 
if [ "$EUID" -ne "0" ]; then echo "Needs su, exiting"; exit 1; fi
 
unset ARGS;ARGS=$#
if [ ! $ARGS -lt "5" ]; then
    DEV=$1
    DIR=`echo $2 | sed 's//$//g'` # Remove trailing slashes from path
    OUTPUTDIR=`echo $4 | sed 's//$//g'` # Remove trailing slashes from path
 
    # Create the log file directory if it doesn't exist
    if [ ! -d "$OUTPUTDIR" ]; then mkdir -p $OUTPUTDIR;fi
 
    # Check the test directory
    if [ ! -d "$DIR" ]; then
        echo "Error: Is $DIR a directory?"
        exit 1
    fi
 
    # Check the device name
    MDDEV="md*"
    HPDEV="c?d?"
    case "$DEV" in
        $HPDEV ) # HP RAID
            unset SYSDEV;SYSDEV="/sys/block/cciss!$DEV/queue/scheduler"
            unset MD;declare -i MD;MD=0
        ;;
        $MDDEV ) # mdadm RAID
            echo "Found a Linux MD device, checking for schedulers..."
            unset MD;declare -i MD;MD=1
            unset SYSDEV
            SYSDEV=$(mdadm -D /dev/md0 | grep active | awk -F '/' '{print $3}' | sed 's/[0-9]//g')
        ;;
        * )
            unset SYSDEV;SYSDEV="/sys/block/$DEV/queue/scheduler"
            unset MD;declare -i MD;MD=0
        ;;
    esac
 
    # Check for the output log
    unset OUTPUTLOG;OUTPUTLOG="$OUTPUTDIR/iozone-$DEV-all-results.log"
    if [ -e "$OUTPUTLOG" ]; then echo "$OUTPUTLOG exists, aborting"; exit 1;fi
 
    # Find available schedulers
    if [ $MD -eq 0 ]; then
        echo "not md device"
        declare -a SCHEDULERS
        SCHEDULERS=`cat $SYSDEV | sed 's/[//g' | sed 's/]//g'`
    else
        declare -a SCHEDULERS; unset MDMEMBER
        for MDMEMBER in ${SYSDEV[@]}; do
            unset SYSDEVMD;SYSDEVMD="/sys/block/"$MDMEMBER"/queue/scheduler"
        done
        SCHEDULERS=`cat $SYSDEVMD | sed 's/[//g' | sed 's/]//g'`
    fi
    if [ -z "$SCHEDULERS" ]; then
        echo "No schedulers found! Wrong device specified? Tried looking in $SYSDEV"
        exit 1
    else
        echo "Schedulers found under $DEV: "$SCHEDULERS
        SIZE=$(($3*1024)) # Size is now MB per thread
        unset RUNS; declare -i RUNS;RUNS=$5
    fi
 
    # Set record size
    if [ -z "$6" ]; then
        echo "Using the default record size of 16MiB"
        RECORDSIZE="16384" # Set default to 16MB
    else
        RECORDSIZE=$6"m"
    fi
 
    # Set no. threads
    if [ -z "$7" ]; then
        echo "Testing with 1, 2 "amp; 3 threads (default)"
        THREADS=3
    else
        THREADS=$7
    fi
 
    SHELL=`which bash`
else
    echo "# Usage:"
    echo "`basename $0`     <#runs> 
"
    echo "time `basename $0` sda /mnt 20480 /dev/shm/server1 3 16 3"
    echo "# The above command will test sda with 1, 2 " 3 threads 3 times per scheduler with 20GiB of data using"
    echo "# 16MiB record size and save logs in /dev/shm/server1/ ."
    echo "# If the record size is omitted the default of 16MiB will be used. (should be buffer size of device)"
    echo "# For HP RAID controllers use device name format c0d0 or c1d2 etc."
    exit 1
fi
 
function createOutputLog () {
    unset FILE
    echo -e "TesttThroughput (KB/s)tI/O SchedulertThreadstn" > $OUTPUTLOG
    for FILE in $OUTPUTDIR/$DEV*.txt; do
        # results
        unset WRITE;unset REWRITE; unset RREAD; unset MIXED; unset RWRITE
        # Scheduler, threads, iteration
        unset SCHED;unset T; unset I;unset IT
        SCHED=`echo "$FILE" | awk -F'-' '{print $2}'`
        T=`echo "$FILE" | awk -F'-' '{print $3}' | sed 's/t//g'`
        # FIXME, it's ugly
        IT=`echo "$FILE" | awk -F'-' '{print $4}'`
        I=`expr ${IT:1:1}`
 
        # Get values
        WRITE=`grep "  Initial write " $FILE | awk '{print $5}'`
        REWRITE=`grep "        Rewrite " $FILE | awk '{print $4}'`
        RREAD=`grep "    Random read " $FILE | awk '{print $5}'`
        MIXED=`grep " Mixed workload " $FILE | awk '{print $5}'`
        RWRITE=`grep "   Random write " $FILE | awk '{print $5}'`
        # echo "iwrite $WRITE rwrite $REWRITE rread $RREAD mixed $MIXED random $RWRITE"
 
        # Print to the file
        if [ -z "$WRITE" -o -z "$REWRITE" -o -z "$RREAD" -o -z "$MIXED" -o -z "$RWRITE" ]; then
            # Something's wrong with our input file, or bug in script
            echo "BUG, unable to parse result:"
            echo "write $WRITE rewrite $REWRITE random read $RREAD mixed $MIXED random write $RWRITE"
            exit 1
        else
            echo -e "Initial writet$WRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Rewritet$RWRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Random readt$RREADt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Mixed workloadt$MIXEDt$SCHEDt$Tt$I" >> $OUTPUTLOG
            echo -e "Random writet$RWRITEt$SCHEDt$Tt$I" >> $OUTPUTLOG
        fi
    done
}
 
unset ITERATIONS; declare -i ITERATIONS; ITERATIONS=0
unset CURRENTTHREADS; declare -i CURRENTTHREADS
unset IOZONECMD
 
cd "$DIR"
echo "Using iozone at `which iozone`"
 
until [ "$ITERATIONS" -ge "$RUNS" ]; do
    let ITERATIONS=$ITERATIONS+1
    for SCHEDULER in $SCHEDULERS; do
        # Change the scheduler
        if [ $MD -eq 1 ]; then
            unset MEMBER
            for MEMBER in $SYSDEV; do
                echo $SCHEDULER > /sys/block/$MEMBER/queue/scheduler
            done
        else
            echo $SCHEDULER > $SYSDEV
        fi
        CURRENTTHREADS=1
        # Repeat until we've tested with all requested threads
        until [ $CURRENTTHREADS -gt $THREADS ]; do
            unset IOZONECMDAPPEND
            IOZONECMDAPPEND="$OUTPUTDIR/$DEV-$SCHEDULER-t$CURRENTTHREADS-i$ITERATIONS.txt"
            #echo "iozonecmdappend is $IOZONECMDAPPEND"
            # Append all test files to the command line (threads/processes)
            unset I; unset IOZONECMD_FILES
            for I in `seq 1 $CURRENTTHREADS`; do
                IOZONECMD_FILES="$IOZONECMD_FILES$DIR/iozone-temp-$I "
            done
            # Drop caches
            echo 3 > /proc/sys/vm/drop_caches
            echo "Testing $SCHEDULER with $CURRENTTHREADS thread(s), run #$ITERATIONS"
            IOZONECMD="iozone -R -i 0 -i 2 -i 8 -s $SIZE -r $RECORDSIZE -b $OUTPUTDIR/$DEV-$SCHEDULER-t$CURRENTTHREADS-i$ITERATIONS.xls -l 1 -u $CURRENTTHREADS -F $IOZONECMD_FILES"
            # Run the command
            echo time $IOZONECMD
            time $IOZONECMD | tee -a $IOZONECMDAPPEND
            # Done testing $CURRENTTHREADS threads/processes, increase to test one more in the loop (if applicable)
            let CURRENTTHREADS=$CURRENTTHREADS+1
        done
    done
    echo "Run #$ITERATIONS done" | tee -a $IOZONECMDAPPEND
done
 
echo
createOutputLog
echo "Done, logs saved in $OUTPUTDIR"
exit 0
