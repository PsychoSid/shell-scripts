#!/bin/bash
HOSTNAME=`hostname`
rhel_release()
{
  awk '
    /Red Hat.*release 5/            { print "5" }
    /Red Hat.*release 6/            { print "6" }
    /Red Hat.*release 7/            { print "7" }
  ' /etc/redhat-release
}

export RHELVER=$(rhel_release)

if [ ${RHELVER} -eq 5 ]; then
  cat > /tmp/dftotal.awk << EOF
BEGIN {
  map[0] = "K"
  map[1] = "M"
  map[2] = "G"
  map[3] = "T"
}
function fmt(val,    c) {
  c=0
  while (val > 1024) {
    c++
    val = val / 1024
  }
  return val map[c]
}

{
  for (i=2;i<5;i++) {
    sum[i]+=\$i
  }
}

END {
  print fmt(sum[2]) "," fmt(sum[3]) "," fmt(sum[4]) "," ((sum[3] / sum[2]) * 100) "%"
}
EOF

  echo "${HOSTNAME},`df -P --local | awk -f /tmp/dftotal.awk`"
else
  df -h --local --total | grep total | while read TOTAL SIZE USED AVAIL PERCENT DUMMY
  do
    echo "${HOSTNAME},${SIZE},${USED},${AVAIL},${PERCENT}"
  done
fi
exit 0



