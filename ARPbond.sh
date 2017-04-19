#!/bin/bash

usage() {
echo "Option not known"
echo " Usage: $0  -b <bond i/f> -m <mod.conffile> -i <arp_interval> -t <arp_ip_target>"
echo " or just run the script for auto settings"
}

# process command line arguments

while getopts "b:m:i:t:" opt
do
   case $opt in
      b)     BOND=$OPTARG;;
      m)     MODFILE=$OPTARG;;
      i)     INTERVAL=$OPTARG;;
      t)     ARPTARG=$OPTARG;;
      \?)    usage
             exit 2;;
   esac
done
shift `expr $OPTIND - 1`
#
OS=`uname -r`
if [ "$MODFILE" = "" ] ; then
        case $OS in
        2.4*)   MODFILE=/etc/modules.conf  ;;
        2.6*)   MODFILE=/etc/modprobe.conf ;;
        *)      MODFILE=/etc/modules.conf ;;
        esac
fi
BOND=${BOND:-0}
INTERVAL=${INTERVAL:-200}
DEFROUTE=`ip route list match 0/0 | cut -d' ' -f3`
ARPTARG=${ARPTARG:-$DEFROUTE}

# change the modfile
DATE=`date +%Y%m%d`
/bin/sed -i-$DATE "s/^options bond$BOND .*mii.*/options bond$BOND mode=1 arp_interval=$INTERVAL arp_ip_target=$ARPTARG/" $MODFILE

