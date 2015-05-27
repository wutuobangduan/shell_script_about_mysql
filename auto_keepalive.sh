#!/bin/bash

MYNAME=`basename $0`
n=`cat /root/mysqlRds/real_server.txt | wc -l`
my_usage()
{
  cat <<EOF
Usage:${MYNAME} [options]
Valid options are:
  -h                     help, Display this message
  -u user_name           mysql user name
  -v                     version num, Valid values "55", "56"
  -I virtual_router_id   The virtual router id of keepalived.conf
  -l lo_value            The values of lo on real server
  -V vip                 The virtual read ip
EOF
}

#my_usage

mysql_user=
mysql_passwd=
mysql_version=55
virtual_router_id=
lo_value=
virtual_ip=
while getopts "u:I:l:V:v:h" opt
do
    case $opt in
        u) mysql_user=$OPTARG;;
        I) virtual_router_id=$OPTARG;;
        l) lo_value=$OPTARG;;
        V) virtual_ip=$OPTARG;;
        v) mysql_version=$OPTARG;;
        h) my_usage;exit 0;;
    *) my_usage;exit 1;;
    esac
done


if [ "${mysql_user}" == "" ]
then
  read -p "Please input the MySQL user[The user of Master and Slave should be same]: " $mysql_user
fi

echo "`date` - [info] MySQL user name is : $mysql_user"

if [ "${virtual_router_id}" == "" ]
then
  read -p "Please input the Virtual Router ID[The Virtual Router ID should be different from other cluster]: " $virtual_router_id
fi
echo "`date` - [info] The value of Virtual Router ID is : $virtual_router_id"

if [ "${lo_value}" == "" ]
then
  read -p "Please input the value of lo[Each vip has different lo value]: " $lo_value
fi

echo "`date` - [info] The value of lo is : $lo_value"

if [ "${virtual_ip}" == "" ]
then
  read -p "Please input the virtual ip address: " $virutal_ip
fi

echo "`date` - [info] The virtual read ip is : $virtual_ip"

echo "`date` - [info] Begin to install keepalived..."

ip1=`cat /root/mysqlRds/lvs_server.txt | awk -F' ' 'NR==1{print $1}'`
echo "`date` - [info] The master lvs server is : $ip1"

ip2=`cat /root/mysqlRds/lvs_server.txt | awk -F' ' 'NR==2{print $1}'`
echo "`date` - [info] The slave lvs server is : $ip2"

check_rpm()
{ 
  lvs_num=`cat /root/mysqlRds/lvs_server.txt | wc -l`
  for((i=1;i<=lvs_num;i++))
  do
    lvs_server=`cat /root/mysqlRds/lvs_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    ipvsadm_file=`ssh $lvs_server "rpm -qa | grep ipvsadm"`
    if [ "$ipvsadm_file" == "" ]
    then
      echo "`date` - [info] We need to install ipvsadm on $lvs_server..."
      ssh $lvs_server "yum -y install ipvsadm"
    else
      echo "`date` - [info] We have installed ipvsadm on $lvs_server,so there is no need to install ipvsadm again..."
    fi
    snmp_file=`ssh $lvs_server "rpm -qa | grep net-snmp"`  
    if [ "$snmp_file" == "" ]
    then
      echo "`date` - [info] We need to install net-snmp on $lvs_server..."
      ssh $lvs_server "yum -y install net-snmp"
    else
      echo "`date` - [info] We have installed net-snmp on $lvs_server,so there is no need to install net-snmp again..."
    fi
    keepalived_file=`ssh $lvs_server "rpm -qa | grep keepalived"` 
    if [ "$keepalived_file" == "" ]
    then
      echo "`date` - [info] We need to install keepalived on $lvs_server..."
      ssh $lvs_server "yum -y install keepalived"
    else
      echo "`date` - [info] We have installed keepalived on $lvs_server,so there is no need to install keepalived again..."
    fi
  done
}


get_master_port()
{
  master_ip=`cat /root/mysqlRds/ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_port=`ssh $master_ip su - $mysql_user <<!
      cat ~/etc/my.cnf | grep -w port | head -2
      exit
!`
  master_port=`echo "$master_port" | awk -F'=' 'NR==2{print $2}' | sed 's/^ //'`
  echo $master_port
}
#get_master_port


#virtual_ip=`get_vip`
#virtual_ip=`echo "$virtual_ip" | awk 'NR==2{print $0}'`

port=`get_master_port`
echo "`date` - [info] The connect port is : $port"


##  lvs and real server on same machine
modify_master_conf1()
{
  ssh $ip1 "cat /dev/null >/etc/keepalived/keepalived.conf"
  ssh $ip1 "echo 'global_defs {' >/etc/keepalived/keepalived.conf"
  ssh $ip1 "sed -i '/global_defs/a\   notification_email {\n      #user@example.com\n   }\n   notification_email_from mail@example.org\n   #smtp_server 192.168.200.1\n   smtp_connect_timeout 30\n   router_id LVS_DEVEL\n}\nvrrp_instance VI_1 {\n    state BACKUP\n    interface eth0\n    virtual_router_id $virtual_router_id\n    priority 150\n    advert_int 1\n    #mcast_src_ip 10.19.90.212\n    authentication {\n        auth_type PASS\n        auth_pass 1111\n    }\n                track_script {\n                chk_mha\n       }\n    #VIP\n    virtual_ipaddress {\n       $virtual_ip\n    }\n}\nvirtual_server fwmark 3 {\n        delay_loop 10\n        lb_algo rr\n        lb_kind DR\n#    persistence_timeout 2\n        protocol TCP\n}' /etc/keepalived/keepalived.conf"
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    ssh $ip1 "sed -i '/protocol/a\        real_server $real_server $port {\n                weight 3\n                TCP_CHECK {\n                        connect_timeout 10\n                        nb_get_retry 3\n                    delay_before_retry 3\n                        connect_port $port\n                }\n        }\n' /etc/keepalived/keepalived.conf"
  done
}



##  lvs and real server on diffrent machine
modify_master_conf2()
{
  ssh $ip1 "cat /dev/null >/etc/keepalived/keepalived.conf"
  ssh $ip1 "echo 'global_defs {' >/etc/keepalived/keepalived.conf"
  ssh $ip1 "sed -i '/global_defs/a\   notification_email {\n      #user@example.com\n   }\n   notification_email_from mail@example.org\n   #smtp_server 192.168.200.1\n   smtp_connect_timeout 30\n   router_id LVS_DEVEL\n}\nvrrp_instance VI_1 {\n    state BACKUP\n    interface eth0\n    virtual_router_id $virtual_router_id\n    priority 150\n    advert_int 1\n    #mcast_src_ip 10.19.90.212\n    authentication {\n        auth_type PASS\n        auth_pass 1111\n    }\n                track_script {\n                chk_mha\n       }\n    #VIP\n    virtual_ipaddress {\n       $virtual_ip dev eth0\n    }\n}\nvirtual_server $virtual_ip $port {\n        delay_loop 10\n        lb_algo rr\n        lb_kind DR\n#    persistence_timeout 2\n        protocol TCP\n}' /etc/keepalived/keepalived.conf"
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    ssh $ip1 "sed -i '/protocol/a\        real_server $real_server $port {\n                weight 3\n                TCP_CHECK {\n                        connect_timeout 10\n                        nb_get_retry 3\n                    delay_before_retry 3\n                        connect_port $port\n                }\n        }\n' /etc/keepalived/keepalived.conf"
  done
}


#modify_master_conf

## lvs and real server on same machine
modify_slave_conf1()
{
  ssh $ip2 "cat /dev/null >/etc/keepalived/keepalived.conf"
  ssh $ip2 "echo 'global_defs {' >/etc/keepalived/keepalived.conf"
  ssh $ip2 "sed -i '/global_defs/a\   notification_email {\n      #user@example.com\n   }\n   notification_email_from mail@example.org\n   #smtp_server 192.168.200.1\n   smtp_connect_timeout 30\n   router_id LVS_DEVEL\n}\nvrrp_instance VI_1 {\n    state BACKUP\n    interface eth0\n    virtual_router_id $virtual_router_id\n    priority 100\n    advert_int 1\n    #mcast_src_ip 10.19.90.212\n    authentication {\n        auth_type PASS\n        auth_pass 1111\n    }\n                track_script {\n                chk_mha\n       }\n    #VIP\n    virtual_ipaddress {\n       $virtual_ip #èæIP\n    }\n}\nvirtual_server fwmark 4 {\n        delay_loop 10\n        lb_algo rr\n        lb_kind DR\n#    persistence_timeout 2\n        protocol TCP\n}' /etc/keepalived/keepalived.conf"
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    ssh $ip2 "sed -i '/protocol/a\        real_server $real_server $port {\n                weight 3\n                TCP_CHECK {\n                        connect_timeout 10\n                        nb_get_retry 3\n                    delay_before_retry 3\n                        connect_port $port\n                }\n        }\n' /etc/keepalived/keepalived.conf"
  done
}

##  lvs and real server on diffrent machine
modify_slave_conf2()
{
  ssh $ip2 "cat /dev/null >/etc/keepalived/keepalived.conf"
  ssh $ip2 "echo 'global_defs {' >/etc/keepalived/keepalived.conf"
  ssh $ip2 "sed -i '/global_defs/a\   notification_email {\n      #user@example.com\n   }\n   notification_email_from mail@example.org\n   #smtp_server 192.168.200.1\n   smtp_connect_timeout 30\n   router_id LVS_DEVEL\n}\nvrrp_instance VI_1 {\n    state BACKUP\n    interface eth0\n    virtual_router_id $virtual_router_id\n    priority 100\n    advert_int 1\n    #mcast_src_ip 10.19.90.212\n    authentication {\n        auth_type PASS\n        auth_pass 1111\n    }\n                track_script {\n                chk_mha\n       }\n    #VIP\n    virtual_ipaddress {\n       $virtual_ip dev eth0\n    }\n}\nvirtual_server $virtual_ip $port {\n        delay_loop 10\n        lb_algo rr\n        lb_kind DR\n#    persistence_timeout 2\n        protocol TCP\n}' /etc/keepalived/keepalived.conf"
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    ssh $ip2 "sed -i '/protocol/a\        real_server $real_server $port {\n                weight 3\n                TCP_CHECK {\n                        connect_timeout 10\n                        nb_get_retry 3\n                    delay_before_retry 3\n                        connect_port $port\n                }\n        }\n' /etc/keepalived/keepalived.conf"
  done
}


#modify_slave_conf


modify_sysctl_conf()
{
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "`date` - [info] Begin to check sysctl.conf on $real_server..."
    ssh $real_server "sed -i '/net.ipv4.conf.all.send_redirects/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.default.send_redirects/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.eth0.send_redirects/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.lo.arp_ignore/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.lo.arp_announce/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.all.arp_ignore/d' /etc/sysctl.conf;sed -i '/net.ipv4.conf.all.arp_announce/d' /etc/sysctl.conf;"
    echo "`date` - [info] Begin to add some arguments on $real_server..."
    ssh $real_server "sed -i '/kernel\.shmall/a\net.ipv4.conf.all.send_redirects = 0\nnet.ipv4.conf.default.send_redirects = 0\nnet.ipv4.conf.eth0.send_redirects = 0\nnet.ipv4.conf.lo.arp_ignore = 1\nnet.ipv4.conf.lo.arp_announce = 2\nnet.ipv4.conf.all.arp_ignore = 1\nnet.ipv4.conf.all.arp_announce = 2' /etc/sysctl.conf"
    echo "`date` - [info] Make the arguments to take effect on $real_server..."
    ssh $real_server "/sbin/sysctl -p"
  done
}

#modify_sysctl_conf

modify_real_server()
{
  for((i=1;i<=$n;i++))
  do
    real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "`date` - [info] Begin to add vip on $real_server's local network interface card..."
    ssh $real_server "ifconfig lo:$lo_value $virtual_ip broadcast $virtual_ip netmask 255.255.255.255 up"
    ssh $real_server "route add -host $virtual_ip dev lo:$lo_value"
  done
}

configure_iptables()
{
  master_physical=`ssh $ip1 "ifconfig | head -1"`
  master_physical_addr=`echo $master_physical | awk '{print $5}'`
  echo "`date` - [info] The physical address on $ip1 is : $master_physical_addr" 
  slave_physical=`ssh $ip2 "ifconfig | head -1"`
  slave_physical_addr=`echo $slave_physical | awk '{print $5}'`
  echo "`date` - [info] The physical address on $ip2 is : $slave_physical_addr"
  
  echo "`date` - [info] check iptables status on $ip1..."
  status1=`ssh $ip1 "service iptables status | grep stopped"`
  if [ "$status1" == "" ]
  then
    echo "`date` - [info] Iptables is running on $ip1,begin to stop iptables..."
    ssh $ip1 "service iptables stop"
  else
    echo "`date` - [info] Iptables is stopped on $ip1,continue..."
  fi
  echo "`date` - [info] Begin to configure iptables on $ip1..."
  echo "The port is : $port"
  ssh $ip1 "iptables -t mangle -I PREROUTING -d $virtual_ip -p tcp -m tcp --dport $port -m mac  ! --mac-source $slave_physical_addr -j MARK --set-mark 0x3"
  echo "`date` - [info] Begin to check iptables status on $ip1..."
  ssh $ip1 "service iptables status"
  status2=`ssh $ip2 "service iptables status | grep stopped"`
  if [ "$status2" == "" ]
  then
    echo "`date` - [info] Iptables is running on $ip2,begin to stop iptables..."
    ssh $ip2 "service iptables stop"
  else
    echo "`date` - [info] Iptables is stopped on $ip2,continue..."
  fi
  echo "`date` - [info] Begin to configure iptables on $ip2..."
  ssh $ip2 "iptables -t mangle -I PREROUTING -d $virtual_ip -p tcp -m tcp --dport $port -m mac  ! --mac-source $master_physical_addr -j MARK --set-mark 0x4"
  echo "`date` - [info] Begin to check iptables status on $ip2..."
  ssh $ip2 "service iptables status"
}

#modify_real_server
#configure_iptables

check_lvs_real()
{
  m=`cat /root/mysqlRds/lvs_server.txt | wc -l`
  n=`cat /root/mysqlRds/real_server.txt | wc -l`
  for((i=1;i<=$m;i++))
  do
    lvs_server=`cat /root/mysqlRds/lvs_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    for((j=1;j<=$n;j++))
    do
      real_server=`cat /root/mysqlRds/real_server.txt | awk -F' ' -v line=$j 'NR==line{print $1}'`
      if [ "${lvs_server}" == "${real_server}" ]
      then
         echo 1
         break 2
      fi
    done
  done
}

#check_lvs_real

configure_keepalived()
{
  check_lvs_real_conf=`check_lvs_real`
  if [ "${check_lvs_real_conf}" == "1" ]
  then
    echo "===============================Modify Keepalived Configure Files================================="
    echo "`date` - [info] The Second Step is to modify keepalived configure files..."
    echo "`date` - [info] Lvs and Real-server on same machine,so we use fwmark configuration..."
    echo "`date` - [info] Begin to configure master configuration files..."
    modify_master_conf1
    echo "`date` - [info] Begin to configure slave configuration files..."
    modify_slave_conf1
    echo "=========================Modify Keepalived Configure Files Finished=============================="
    echo
    echo
    echo
    echo "=======================================Modify Sysctl.conf========================================"
    echo "`date` - [info] The Third Step is to modify sysctl.conf on master and slave..."
    modify_sysctl_conf
    echo "=====================================Modify Sysctl.conf Finished================================="
    echo
    echo
    echo
    echo "=======================================Modify real server========================================"
    echo "`date` - [info] The Forth Step is to add vip on real server..."
    modify_real_server
    echo "====================================Modify real server finished=================================="
    echo
    echo
    echo
    echo "=======================================Configure Iptables========================================"
    echo "`date` - [info] The Fifth Step is to configure iptables..."
    configure_iptables
    echo "==================================Configure Iptables Finished===================================="
    echo "`date` - [info] We have configured keepalived successfully!"
  else
    echo "===============================Modify Keepalived Configure Files================================="
    echo "`date` - [info] The Second Step is to modify keepalived configure files..."
    echo "`date` - [info] Lvs and Real-server on different machine,so we use virtual-ip configuration..."
    echo "`date` - [info] Begin to configure master configuration files..."
    modify_master_conf2
    echo "`date` - [info] Begin to configure slave configuration files..."
    modify_slave_conf2
    echo "=========================Modify Keepalived Configure Files Finished=============================="
    echo
    echo
    echo
    echo "=======================================Modify Sysctl.conf========================================"
    echo "`date` - [info] The Third Step is to modify sysctl.conf on master and slave..."
    modify_sysctl_conf
    echo "=====================================Modify Sysctl.conf Finished================================="
    echo
    echo
    echo
    echo "=======================================Modify real server========================================"
    echo "`date` - [info] The Forth Step is to add vip on real server..."
    modify_real_server
    echo "====================================Modify real server finished=================================="
    echo "`date` - [info] We have configured keepalived successfully!"
  fi
  
}

check_start_keepalived()
{
  lvs_num=`cat /root/mysqlRds/lvs_server.txt | wc -l`
  for((i=1;i<=$lvs_num;i++))
  do
    lvs_server=`cat /root/mysqlRds/lvs_server.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    status=`ssh $lvs_server "service keepalived status | grep stopped"`
    if [ "$status" == "" ]
    then
      echo "`date` - [info] Keepalived is running on $lvs_server,begin to stop iptables..."
      ssh $lvs_server "/etc/init.d/keepalived stop"
    else
      echo "`date` - [info] Keepalived is stopped on $lvs_server,continue..."
    fi
    echo "`date` - [info] Begin to start keepalived on $lvs_server..."
    ssh $lvs_server "/etc/init.d/keepalived start"
    echo "`date` - [info] Begin to check keepalived status on $lvs_server..."
    ssh $lvs_server "/etc/init.d/keepalived status"
  done
}




auto_keepalived()
{
  echo "================================================================================================="
  echo "`date` - [info] Begin to install keepalived automatically!"
  echo
  echo
  echo
  echo "============================================Auto SSH============================================="
  echo "`date` - [info] The first Step is to check rpm files..."
  check_rpm
  echo "=====================================check rpm files Finished===================================="
  echo
  echo
  echo
  configure_keepalived
  echo
  echo
  echo
  echo "==================================Check And Start Keepalived====================================="
  echo "`date` - [info] The Sixth Step is to check and start keepalived..."
  check_start_keepalived
  echo "==============================Check And Start Keepalived Finished================================"
}

auto_keepalived
