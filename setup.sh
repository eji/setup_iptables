#!/bin/sh
# 
# Usage: sudo ./setup.sh
#

if [ "root" != $(whoami) ]; then
  echo "Please run as root." >&2
  exit 1
fi

MYHOST=$(/sbin/ifconfig eth0 | grep 'inet addr:' | sed -e 's/^.*inet addr://' -e 's/ .*//')
if [ "" = "${MYHOST}" ]; then
  echo "Don't know the IP of this host." >&2
  exit 2
fi
MYHOST_SSHD_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
if [ "" = "${MYHOST_SSHD_PORT}" ]; then
  echo "Don't know the sshd port of this host." >&2
  exit 3
fi
ANY_HOST='0.0.0.0/0'

# Flush & Reset
################
iptables -F
iptables -X

# Default Rules
#################
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# loopback
###########
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Deny from private network address
#####################################
iptables -A INPUT -s 10.0.0.0/8 -j DROP
iptables -A INPUT -s 172.16.0.0/12 -j DROP
iptables -A INPUT -s 192.168.0.0/16 -j DROP

# ICMP ANY_HOST -> MYHOST (ping)
###################################
# long term
iptables -A INPUT -p icmp --icmp-type echo-request -s $ANY_HOST -d $MYHOST -m limit --limit 1/m --limit-burst 10 -j ACCEPT
# short term
#iptables -A INPUT -p icmp --icmp-type echo-request -s $ANY_HOST -d $MYHOST -m limit --limit 1/m --limit-burst 5 -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type echo-reply -s $MYHOST -d $ANY_HOST -j ACCEPT

# ICMP MYHOST -> ANYHOST (ping)
####################################
iptables -A OUTPUT -p icmp --icmp-type echo-request -s $MYHOST -d $ANY_HOST -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -s $ANY_HOST -d $MYHOST -j ACCEPT

# ssh ANY_HOST -> MYHOST
#############################
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
iptables -A INPUT -p tcp -m state --state NEW,ESTABLISHED,RELATED -s $ANY_HOST -d $MYHOST --dport $MYHOST_SSHD_PORT -j ACCEPT
iptables -A OUTPUT -p tcp -s $MYHOST --sport $MYHOST_SSHD_PORT -d $ANY_HOST -j ACCEPT

# ssh MYHOST -> ANY_HOST
############################
SSHD_PORT=22
iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -s $ANY_HOST --sport $SSHD_PORT -d $MYHOST -j ACCEPT
iptables -A OUTPUT -p tcp ! --syn -m state --state NEW -s $MYHOST -d $ANY_HOST --dport $SSHD_PORT -j DROP
iptables -A OUTPUT -p tcp -s $MYHOST -d $ANY_HOST --dport $SSHD_PORT -j ACCEPT

# http ANY -> MYHOST
#########################
HTTP_PORT=80
#iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
#iptables -A INPUT -p tcp -m state --state NEW,ESTABLISHED,RELATED -s $ANY_HOST -d $MYHOST --dport $HTTP_PORT -j DROP
#iptables -A OUTPUT -p tcp -s $MYHOST --sport $HTTP_PORT -d $ANY_HOST -j ACCEPT

# https ANY -> MYHOST
#########################
HTTPS_PORT=443
#iptables -A INPUT -p tcp -m state --state NEW,ESTABLISHED,RELATED -s $ANY_HOST -d $MYHOST --dport $HTTPS_PORT -j ACCEPT
#iptables -A OUTPUT -p tcp -s $MYHOST --sport $HTTPS_PORT -d $ANY_HOST -j ACCEPT

# http MYHOST -> ANY
########################
iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -s $ANY_HOST --sport $HTTP_PORT -d $MYHOST -j ACCEPT
iptables -A OUTPUT -p tcp ! --syn -m state --state NEW -s $MYHOST -d $ANY_HOST --dport $HTTP_PORT -j DROP
iptables -A OUTPUT -p tcp -s $MYHOST -d $ANY_HOST --dport $HTTP_PORT -j ACCEPT

# https MYHOST -> ANY
########################
iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -s $ANY_HOST -d $MYHOST -j ACCEPT
iptables -A OUTPUT -p tcp ! --syn -m state --state NEW -s $MYHOST -d $ANY_HOST --dport $HTTPS_PORT -j DROP
iptables -A OUTPUT -p tcp -s $MYHOST -d $ANY_HOST --dport $HTTP_PORT -j ACCEPT
iptables -A OUTPUT -p tcp -s $MYHOST -d $ANY_HOST --dport $HTTPS_PORT -j ACCEPT

# dns MYHOST -> ANY
##########################
DNS_PORT=53
iptables -A INPUT -p udp -s $ANY_HOST --sport $DNS_PORT -d $MYHOST -j ACCEPT
iptables -A OUTPUT -p udp -s $MYHOST -d $ANY_HOST --dport $DNS_PORT -j ACCEPT

# mangle table (for QoS)
##########################
iptables -A PREROUTING -t mangle -p tcp --sport $MYHOST_SSHD_PORT -j TOS --set-tos Minimize-Delay
iptables -A PREROUTING -t mangle -p tcp --sport $HTTP_PORT -j TOS --set-tos Maximize-Throughput

# Logging
##########
iptables -N LOGGING
iptables -A LOGGING -j LOG --log-level warning --log-prefix "DROP:" -m limit
iptables -A LOGGING -j DROP
iptables -A INPUT -j LOGGING
iptables -A OUTPUT -j LOGGING

exit 0
