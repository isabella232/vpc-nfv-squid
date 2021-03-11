#!/bin/bash
set -e

success=false
trap check_finish EXIT
check_finish() {
  if [ $success = true ]; then
    echo '>>>' success
  else
    echo "FAILED"
  fi
}

log() {
  echo
  echo '>>>' "$*"
}

ssh_it() {
  host=$1; shift
  jumpfip=$(terraform output -raw fip_jump)
  echo ssh -J root@$jumpfip root@$host "$*"
  ssh -o "StrictHostKeyChecking no" -J root@$jumpfip root@$host "$*"
}

FILE_URL=neverssl.com
FILE_CONTENTS="poorly-behaved"

host_test() {
  host=$1
  log verify it is possible to ssh through the jump host by executing the true command on host.  All subsequent commands jump through.
  ssh_it $host true

  # it should be possible to ping the proxy
  proxy=$(terraform output -raw ip_proxy)
  log verify proxy connectivity using ping
  ssh_it $host ping $proxy -c 2

  # access a white listed website but use curls --proxy to explicitly go to squid.  This does not test
  # routing capability since routing to a server address in the same VPC is nothing special
  log verify explicy specifying the squid proxy server ip works.  Testing the network path - not testing the router
  ssh_it $host "set -o pipefail; curl $FILE_URL -s --proxy $proxy:8080 | grep $FILE_CONTENTS > /dev/null"

  # typical usage just access something like neverssl.com this is testing the vpc routing table route
  log veriy direct access to $FILE_URL, end to end, through the route table
  ssh_it $host "set -o pipefail; curl $FILE_URL -s | grep $FILE_CONTENTS > /dev/null"

  # check out proxy_user_data.sh only a few web sites are enabled and virus.com is not one of them
  # The error message from squid has the word squid in the message
  log verify implicit access to a denied host fails
  ssh_it $host "curl virus.com -s | grep squid > /dev/null"
}

proxy_test() {
  proxy=$1
  log verify it is possible to ssh through the jump host by executing the true command on host.  All subsequent commands jump through.
  ssh_it $proxy true

  log verify that the squid service is running
  ssh_it $proxy 'set -o pipefail; systemctl is-active squid | grep active'

  log verify curl through the local squid proxy works
  ssh_it $host "set -o pipefail; curl $FILE_URL -s --proxy localhost:8080 | grep $FILE_CONTENTS > /dev/null"
}

proxy=$(terraform output -raw ip_proxy)
proxy_test $proxy

for ip in $(terraform output -json host | jq -r '.[] | .ip_host')
do
  host_test $ip
done
success=true
