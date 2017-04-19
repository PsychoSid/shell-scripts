#!/bin/sh

### BEGIN INIT INFO
# Provides: Firewalling rules
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: enable SSH whitelist on boot
# Description:
### END INIT INFO

# IPTABLE=/sbin/iptables
IPTABLE=/bin/echo

IP_GRANTED="`grep '^sshd:' /etc/hosts.allow | sort -u | awk '{print $2}'`"

# Flush all the tables and rules
$IPTABLE -t filter -F

# Flush personnal rules
$IPTABLE -t filter -X

# Don't break current connections
$IPTABLE -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
$IPTABLE -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# White list SSH
$IPTABLE -N SSH_WHITELIST
for IPADDR in $IP_GRANTED
do
  $IPTABLE -A SSH_WHITELIST -s $IPADDR -m recent --remove --name SSH -j ACCEPT
done

$IPTABLE -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
$IPTABLE -A INPUT -p tcp --dport 22 -m state --state NEW -j SSH_WHITELIST

$IPTABLE -A INPUT -m state --state NEW -p tcp --dport 22 -j DROP
