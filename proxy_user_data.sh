#!/bin/bash
set -ex

echo proxy_user_data
host_ipv4_cidr_block=__ipv4_cidr_block__ # terraform replace
if [ $host_ipv4_cidr_block = "__"ipv4_cidr_block__ ]; then
  # testing on the proxy, not executed in the instance
  host_ipv4_cidr_block=10.0.0.0/14
  cloud-init status --wait
  cloud-init status
fi

apt-get update
apt-get install -y squid

cat > /etc/squid/squid.conf <<EOF
visible_hostname squid

#Handling HTTP requests
http_port 3129 intercept
http_port 8080
acl allowed_http_sites dstdomain .neverssl.com
acl allowed_http_sites dstdomain .test.com
acl allowed_http_sites dstdomain .ubuntu.com
http_access allow allowed_http_sites
EOF

systemctl restart squid
iptables -t nat -I PREROUTING 1 -s $host_ipv4_cidr_block -p tcp --dport 80 -j REDIRECT --to-port 3129

# optional: allows configuration for: tail -f /var/log/kern.log
iptables -A INPUT -s $host_ipv4_cidr_block -j LOG
iptables -A OUTPUT -d $host_ipv4_cidr_block -j LOG
