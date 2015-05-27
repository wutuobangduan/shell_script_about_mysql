#!/bin/bash
rm -rf /root/.ssh/id_rsa
ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ''
n=`cat /mysql/mha/automha/ip_pass.txt | wc -l`
for((i=1;i<=$n;i++))
do
  ip=`cat /mysql/mha/automha/ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
  password=`cat /mysql/mha/automha/ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $2}'`
  /mysql/mha/automha/auto.exp $ip $password
  echo $ip
  ssh root@$ip "ifconfig |grep 'inet addr' |head -1"
done
#host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
#for((i=1;i<=$n;i++))
#do
#  ip=`cat ip_pass.txt | grep -v $host | awk -F' ' -v line=$i 'NR==line{print $1}'`
#  echo $ip
#  ssh root@$ip "/mysql/mysqldp/auto.sh"
#done
