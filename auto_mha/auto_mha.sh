#!/bin/bash

mysql_user=$1
MYNAME=`basename $0`
my_usage()
{
  if [ "$mysql_user" == "" ]
  then  
    echo "`date` - [info] Usage:${MYNAME} [mysql_user]"
    exit
  fi
}
#my_usage
auto_ssh()
{
  rm -rf /root/.ssh/id_rsa
  ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ''
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    password=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $2}'`
    ./autossh.exp $ip $password
    echo $ip
    ssh root@$ip "ifconfig |grep 'inet addr' |head -1"
  done
  host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ip_pass.txt | grep -v $host | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo $ip
    if [ "$ip" = "" ]
    then
      echo "`date` - [info] continue another host!"
    else
      ssh root@$ip "/mysql/mha/automha/auto.sh"
    fi
  done
}

get_master_socketdir()
{
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_socketdir=`ssh $master_ip su - $mysql_user <<!
      cat ~/etc/my.cnf | grep socket | head -2
      exit
!`
  master_socketdir=`echo "$master_socketdir" | awk -F'=' 'NR==2{print $2}' | sed 's/^ //'`
  echo $master_socketdir
}


get_slave_socketdir()
{
  n=`cat ./ip_pass.txt | wc -l`
  mm=$(($1+1))
  for((i=2;i<=$n;i++))
  do
    if [ $mm == $i ]
    then
      slave_ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      slave_socketdir=`ssh $slave_ip su - $mysql_user <<!
         cat ~/etc/my.cnf | grep socket | head -2
      exit
!`
      slave_socketdir=`echo "$slave_socketdir" | awk -F'=' 'NR==2{print $2}' | sed 's/^ //'`
      echo $slave_socketdir
      break
    fi
  done
}



set_replication()
{
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
#begin to configure master
    if [ $i == 1 ]
    then
      ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      echo "`date` - [info] current ip is : $ip"
      master_socketdir=`get_master_socketdir`
      grant_rep=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "grant replication slave on *.* to rep@'%' identified by 'rep'"
      exit
!`
      echo "`date` - [info] grant rep is $?"
      grant_rep=$?
      grant_admin=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "grant all privileges  on *.* to admin@'%' identified by 'admin'"
      exit
!`
      echo "`date` - [info] grant admin is $?"
      grant_admin=$?
      if [ $grant_rep -eq 0 -a $grant_admin -eq 0 ]
      then
         echo "`date` - [info] grant successfull!"
      else
         echo "`date` - [info] grant failed"
      fi
      master_ip=$ip
      master_port=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "select @@port"
      exit
!`
      master_port=`echo $master_port | awk -F' ' '{print $2}'`
      echo "`date` - [info] master port is : $master_port"
      master_log_file=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "show master status\G"| awk -F':' 'NR==2{print $2}'
      exit
!`
      #master_log_file=`mysql -uadmin -padmin -h$ip -P$master_port -e "show master status\G" | awk -F':' 'NR==2{print $2}'`
      master_log_file=`echo $master_log_file|awk -F':' '{print $2}' | sed 's/^ //'`
      echo "`date` - [info] master_log_file is : $master_log_file"
      master_log_pos=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "show master status\G"| awk -F':' 'NR==3{print $2}' | sed 's/^ //'
      exit
!`
      master_log_pos=`echo $master_log_pos|awk -F':' '{print $2}' | sed 's/^ //'`
      echo "`date` - [info] master_log_pos is : $master_log_pos"
#begin to configure slave
    else
      ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      echo "`date` - [info] current ip is : $ip"
      mm=$(($i-1))
      slave_socketdir=`get_slave_socketdir $mm`
      grant_rep=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "grant replication slave on *.* to rep@'%' identified by 'rep'"
      exit
!`
      echo "`date` - [info] grant rep is $?"
      grant_rep=$?
      grant_admin=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "grant all privileges  on *.* to admin@'%' identified by 'admin'"
      exit
!`
      echo "`date` - [info] grant admin is $?"
      grant_admin=$?
      if [ $grant_rep -eq 0 -a $grant_admin -eq 0 ]
      then
         echo "`date` - [info] grant successfull!"
      else
         echo "`date` - [info] grant failed"
      fi
      echo "`date` - [info] $ip is a slave!"
      stop_slave=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "stop slave"
      exit
!`
      stop_slave=$?
      if [ $stop_slave -eq 0 ]
      then
         echo "`date` - [info] stop slave successfull!"
      fi
      change_master=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "change master to master_host='$master_ip',master_port=$master_port,master_user='rep',master_password='rep',master_log_file='$master_log_file',master_log_pos=$master_log_pos"
      exit
!`
      change_master=$?
      if [ $change_master -eq 0 ]
      then
        echo "`date` - [info] change master successfull"
      else
        echo "`date` - [info] change master failed,exit!!"
        exit
      fi
      start_slave=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "start slave"
      exit
!`
      start_slave=$?
      if [ $start_slave -eq 0 ]
      then
        echo "`date` - [info] start slave successfull"
      else 
        echo "`date` - [info] start slave failed,exit!!"
        exit
      fi
      slave_io_running=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "show slave status\G"|grep 'Slave_IO_Running'
      exit
!`
      slave_io_running=`echo $slave_io_running |awk -F':' '{print $2}'|sed 's/^ //'`
      echo "`date` - [info] slave io state is $slave_io_running"
      slave_sql_running=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "show slave status\G"|grep -w 'Slave_SQL_Running'
      exit
!`
      slave_sql_running=`echo $slave_sql_running |awk -F':' '{print $2}'|sed 's/^ //'`
      echo "`date` - [info] slave sql state is $slave_sql_running"
      if [ "$slave_io_running" = "Yes" -a "$slave_sql_running" = "Yes" ]
      then
        echo "`date` - [info] set replication success!!!continue"
      else
        echo "`date` - [info] set replication failed!!!exit"
        exit
      fi
    fi
    
  done
}


#auto_ssh
#set_replication


set_semi_repl()
{
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    if [ $i == 1 ]
    then 
      ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      echo "`date` - [info] current ip is : $ip"
      master_socketdir=`get_master_socketdir`
      check_master_semi=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "show plugins\G" | grep "semisync_master.so"
      exit
!`
      echo "`date` - [info] check master semi result is : $check_master_semi"
      check_slave_semi=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "show plugins\G" | grep "semisync_slave.so"
      exit
!`
      echo "`date` - [info] check slave semi result is : $check_slave_semi"
      if [ "$check_master_semi" = "" -a "$check_slave_semi" = "" ]
      then
        set_semi=`ssh $ip su - $mysql_user <<!
        mysql -uroot -S $master_socketdir -e "install plugin rpl_semi_sync_master soname 'semisync_master.so';set global rpl_semi_sync_master_enabled=1;set global rpl_semi_sync_master_timeout=1000;install plugin rpl_semi_sync_slave soname 'semisync_slave.so';set global rpl_semi_sync_slave_enabled=1;"
        exit
!`
        if [ $? -eq 0 ]
        then 
          echo "`date` - [info] set semi replication successufull!"
        else 
          echo "`date` - [info] set semi replication failed"
        fi
      else
        echo "`date` - [info] There is no need to install semi sync plugin!"
      fi
      modify_my_configure=`ssh $ip su - $mysql_user <<!
      sed -i '/rpl_semi/d' ~/etc/my.cnf
      sed -i '/^query_cache_type/a\rpl_semi_sync_master_enabled=1\nrpl_semi_sync_master_timeout=1000\nrpl_semi_sync_slave_enabled=1' ~/etc/my.cnf
      exit
!`
      if [ $? = 0 ]
      then
        echo "`date` - [info] On $ip,modify my.cnf successfully!"
      else
        echo "`date` - [info] on $ip,modify my.cnf failed!"
        echo "`date` - [info] Please check the script!!!"
      fi
    else
      ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      echo "`date` - [info] current ip is : $ip"
      mm=$(($i-1))
      slave_socketdir=`get_slave_socketdir $mm`
      check_master_semi=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "show plugins\G" | grep "semisync_master.so"
      exit
!`
      echo "`date` - [info] check master semi result is : $check_master_semi"
      check_slave_semi=`ssh $ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "show plugins\G" | grep "semisync_slave.so"
      exit
!`
      echo "`date` - [info] check slave semi result is : $check_slave_semi"
      if [ "$check_master_semi" = "" -a "$check_slave_semi" = "" ]
      then
        set_semi=`ssh $ip su - $mysql_user <<!
        mysql -uroot -S $slave_socketdir -e "install plugin rpl_semi_sync_master soname 'semisync_master.so';set global rpl_semi_sync_master_enabled=1;set global rpl_semi_sync_master_timeout=1000;install plugin rpl_semi_sync_slave soname 'semisync_slave.so';set global rpl_semi_sync_slave_enabled=1;"
        exit
!`
        if [ $? -eq 0 ]
        then
          echo "`date` - [info] set semi replication successufull!"
        else
          echo "`date` - [info] set semi replication failed"
        fi
      else
        echo "`date` - [info] There is no need to install semi sync plugin!"
      fi
      modify_my_configure=`ssh $ip su - $mysql_user <<!
      sed -i '/rpl_semi/d' ~/etc/my.cnf
      sed -i '/^query_cache_type/a\rpl_semi_sync_master_enabled=1\nrpl_semi_sync_master_timeout=1000\nrpl_semi_sync_slave_enabled=1' ~/etc/my.cnf
      exit
!`
      if [ $? = 0 ]
      then
        echo "`date` - [info] On $ip,modify my.cnf successfully!"
      else
        echo "`date` - [info] on $ip,modify my.cnf failed!"
        echo "`date` - [info] Please check the script!!!"
      fi
    fi
  done
}
#set_semi_repl

get_master_port()
{
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_socketdir=`get_master_socketdir`
  master_port=`ssh $master_ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "select @@port"
      exit
!`
  master_port=`echo $master_port | awk -F' ' '{print $2}'`
  echo $master_port
}
#get_master_port

get_master_binlogdir()
{
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_socketdir=`get_master_socketdir`
  master_binlog_full_dir=`ssh $master_ip su - $mysql_user <<!
      mysql -uroot -S $master_socketdir -e "select @@log_bin_basename"
      exit
!`
  master_binlog_full_dir=`echo $master_binlog_full_dir | awk -F' ' '{print $2}'`
  master_binlog_dir=`dirname $master_binlog_full_dir`
  echo $master_binlog_dir
}

#get_master_binlogdir



get_slave_port()
{
  n=`cat ./ip_pass.txt | wc -l`
  mm=$(($1+1)) 
  for((i=2;i<=$n;i++))
  do
    if [ $mm == $i ]
    then
      slave_ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      slave_socketdir=`get_slave_socketdir $1`
      slave_port=`ssh $slave_ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "select @@port"
      exit
!`
      slave_port=`echo $slave_port | awk -F' ' '{print $2}'`
      echo $slave_port
      break
    fi
  done
}
#get_slave_port 2

get_slave_binlogdir()
{ 
  n=`cat ./ip_pass.txt | wc -l`
  mm=$(($1+1))
  for((i=2;i<=$n;i++))
  do
    if [ $mm == $i ]
    then
      slave_ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      slave_socketdir=`get_slave_socketdir $1`
      slave_binlog_full_dir=`ssh $slave_ip su - $mysql_user <<!
      mysql -uroot -S $slave_socketdir -e "select @@log_bin_basename"
      exit
!`
      slave_binlog_full_dir=`echo $slave_binlog_full_dir | awk -F' ' '{print $2}'`
      slave_binlog_dir=`dirname $slave_binlog_full_dir`
      echo $slave_binlog_dir
      break
    fi
  done
}

#get_slave_binlogdir

#LOG=./auto_mha.log
my_log()
{
  echo "$1" 2>&1 | tee -a $LOG
}

create_mhadir()
{ 
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "`date` - [info] current ip is : $ip"
    ssh $ip "[[ -d /mysql/mha/conf ]] && echo 'on $ip configuration dir exits,continue'|| mkdir -p /mysql/mha/conf"
    ssh $ip "[[ -d /mysql/mha/log ]] && echo 'on $ip log dir exits,continue'|| mkdir -p /mysql/mha/log"
    ssh $ip "[[ -d /mysql/mha/install ]] && echo 'on $ip install dir exits,continue'|| mkdir -p /mysql/mha/install"
    ssh $ip "[[ -d /mysql/mha/scripts ]] && echo 'on $ip scripts dir exits,continue'|| mkdir -p /mysql/mha/scripts"
  done
}

#create_mhadir

get_vip()
{
  host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
  vary_host=`echo "$host" | awk -F'.' '{print $1"."$2"."$3"."}'`
  echo $vary_host
  for((i=1;i<=100;i++))
  do
    ping=`ping -c 3 "$vary_host$i" | grep -i "unreachable" | head -1`
    if [ "$ping" != "" ]
    then
      echo "$vary_host$i"
      break
    fi
  done
}
#get_vip
modify_master_ip_online_failover_script()
{
  virtual_ip=`get_vip`
  virtual_ip=`echo "$virtual_ip" | awk 'NR==2{print $0}'`
  echo "`date` - [info] The write Virtual IP is : $virtual_ip"
  sed -i "/my \$vip/{x;s/^/./;/^\.\{1\}$/{x;s/.*/my \$vip = \'$virtual_ip\'\;/;x};x;}" /mysql/mha/scripts/master_ip_failover
  sed -i "/my \$vip/{x;s/^/./;/^\.\{1\}$/{x;s/.*/my \$vip = \'$virtual_ip\'\;/;x};x;}" /mysql/mha/scripts/master_ip_online_change
}
#modify_master_ip_online_failover_script


configure_mha()
{
  ori_mha_conf=/mysql/mha/conf/mha.cnf
  mha_conf=/mysql/mha/conf/mha.conf
  user=admin
  password=admin
  ssh_user=root
  repl_user=rep
  repl_password=rep
  manager_log=/mysql/mha/log/manager.log
  manager_workdir=/mysql/mha/log
  master_ip_failover_script=/mysql/mha/scripts/master_ip_failover
  master_ip_online_change_script=/mysql/mha/scripts/master_ip_online_change
  #> ${mha_conf}
  #cat $ori_mha_conf | grep user | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${user}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep password | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${password}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep ssh_user | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${ssh_user}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep repl_user | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${repl_user}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep repl_password | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${repl_password}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep manager_log | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${manager_log}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep manager_workdir | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${manager_workdir}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep master_ip_failover_script | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${master_ip_failover_script}"'\2,' >> ${mha_conf}
  #cat $ori_mha_conf | grep master_ip_online_change_script | grep -v '#'| head -1 | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${master_ip_online_change_script}"'\2,' >> ${mha_conf}
  #cat
  > ${mha_conf}
  while read inputline
  do
    if echo $inputline | grep -w user | grep -v '#'
    then
      echo "${inputline}" | sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${user}"'\2,' >> ${mha_conf}
      #echo "${inputline}" |sed -e "s,\(.*= *\)[^ ]*\(.*\),\1${user}\2," >> ${mha_conf}
    elif echo $inputline | grep -w password | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${password}"'\2,' >> ${mha_conf}
      #echo "${inputline}" |sed -e "s,\(.*= *\)[^ ]*\(.*\),\1${password}\2," >> ${mha_conf}
    elif echo $inputline | grep -w ssh_user | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${ssh_user}"'\2,' >> ${mha_conf}
      #echo "${inputline}" |sed -e "s,\(.*= *\)[^ ]*\(.*\),\1${ssh_user}\2," >> ${mha_conf}
    elif echo $inputline | grep -w repl_user | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${repl_user}"'\2,' >> ${mha_conf}
    elif echo $inputline | grep -w repl_password | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${repl_password}"'\2,' >> ${mha_conf}
    elif echo $inputline | grep -w manager_log | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${manager_log}"'\2,' >> ${mha_conf}
    elif echo $inputline | grep -w manager_workdir | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${manager_workdir}"'\2,' >> ${mha_conf}
    elif echo $inputline | grep -w master_ip_failover_script | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${master_ip_failover_script}"'\2,' >> ${mha_conf}
    elif echo $inputline | grep -w master_ip_online_change_script | grep -v '#'
    then
      echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${master_ip_online_change_script}"'\2,' >> ${mha_conf}
    else
      echo "${inputline}" >> ${mha_conf}
    fi  
  done < ${ori_mha_conf}
  n=`cat ./ip_pass.txt | wc -l`
  m=$(($n-2))
  if [ $m -gt 0 ]
  then 
    for((i=$n;i>=3;i--))
    do
      ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
      mm=$(($i-1))
      sed -i "/^#slaves/a\[server$i]\nhostname=$ip\nport=`get_slave_port $mm`\ncandidate_master=1\ncheck_repl_delay=0\nmaster_binlog_dir=`get_slave_binlogdir $mm`\nremote_workdir=\/mysql\/mha\/log" /mysql/mha/conf/mha.conf
    done 
  fi
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    if [ $i = 1 ]
    then 
      sed -i "/hostname=.*/{x;s/^/./;/^\.\{1\}$/{x;s/.*/hostname=$ip/;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/port=.*/{x;s/^/./;/^\.\{1\}$/{x;s/.*/port=`get_master_port`/;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/master_binlog_dir=.*/{x;s/^/./;/^\.\{2\}$/{x;s,.*,master_binlog_dir=`get_master_binlogdir`,;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/remote_workdir=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/remote_workdir=\/mysql\/mha\/log/;x};x;}" /mysql/mha/conf/mha.conf
    elif [ $i = 2 ]
    then
      sed -i "/hostname=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/hostname=$ip/;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/port=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/port=`get_slave_port 1`/;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/master_binlog_dir=.*/{x;s/^/./;/^\.\{3\}$/{x;s,.*,master_binlog_dir=`get_slave_binlogdir`,;x};x;}" /mysql/mha/conf/mha.conf
      sed -i "/remote_workdir=.*/{x;s/^/./;/^\.\{3\}$/{x;s/.*/remote_workdir=\/mysql\/mha\/log/;x};x;}" /mysql/mha/conf/mha.conf
    fi
  done
}

get_rpm_cnf_scripts_file()
{ 
  scp_ip=`cat ./scp_ip_pass.txt | awk -F' ' '{print $1}'`
  scp_pass=`cat ./scp_ip_pass.txt | awk -F' ' '{print $2}'`
  ./autoscp.exp $scp_ip $scp_pass
  chmod +x /mysql/mha/scripts/master_ip_online_change
  chmod +x /mysql/mha/scripts/master_ip_failover

  #modify scripts

  modify_master_ip_online_failover_script

  #modify mha configure file
  configure_mha

  host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | grep -v $host | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "`date` - [info] current ip is : $ip"
    if [ "$ip" = "" ]
    then 
      echo "`date` - [info] conitune anoter ip to get files!"
    else
      scp /mysql/mha/conf/* root@$ip:/mysql/mha/conf/
      #scp /mysql/mha/install/*.rpm root@$ip:/mysql/mha/install/
      scp /mysql/mha/scripts/* root@$ip:/mysql/mha/scripts/
    chmod_x=`ssh $ip "chmod +x /mysql/mha/scripts/master_ip_online_change;chmod +x /mysql/mha/scripts/master_ip_failover"`
    if [ $? = 0 ]
    then
      echo "`date` - [info] chmod +x successfully!"
    else
      echo "`date` - [info] chmod +x failed!"
    fi
    fi
  done
}
#get_rpm_cnf_scripts_file

install_rpm()
{  
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "`date` - [info] current ip is : $ip"
    if [ -f /etc/yum.repos.d/mha.repo ]
    then
      cat /dev/null >/etc/yum.repos.d/mha.repo
      echo "[yum-suningmysql]" >/etc/yum.repos.d/mha.repo
      sed -i '/yum/a\name=mha rpm\nbaseurl=http:\/\/10.27.81.9\/yum\ngpgcheck=0\nenabled=1' /etc/yum.repos.d/mha.repo
    else 
      touch /etc/yum.repos.d/mha.repo
      echo "[yum-suningmysql]" >/etc/yum.repos.d/mha.repo
      sed -i '/yum/a\name=mha rpm\nbaseurl=http:\/\/10.27.81.9\/yum\ngpgcheck=0\nenabled=1' /etc/yum.repos.d/mha.repo
    fi
    yum -y install mha4mysql-node mha4mysql-manager
#    ssh $ip "rpm -ivh /mysql/mha/install/Percona-Server-shared-55-5.5.18-rel23.0.203.rhel.x86_64.rpm;rpm -ivh /mysql/mha/install/Percona-Server-client-55-5.5.18-rel23.0.203.rhel.x86_64.rpm;rpm -ivh /mysql/mha/install/MySQL-shared-compat-5.5.35-1.el6.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-Config-Tiny-2.12-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Email-Date-Format-1.002-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Mail-Sender-0.8.16-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Mail-Sendmail-0.79-1.2.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-MIME-Lite-3.029-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Module-Runtime-0.012-1.el6.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Parallel-ForkManager-0.7.5-2.2.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Sys-Syslog-0.27-1.el6.rf.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-TimeDate-1.20-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Try-Tiny-0.09-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Test-Pod-1.45-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Module-Implementation-0.06-1.el6.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Params-Validate-0.95-1.el6.rfx.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-MailTools-2.12-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Log-Dispatch-2.26-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-DBD-MySQL-4.022-1.el6.rfx.x86_64.rpm;" 
#    ssh $ip "cd /mysql/mha/install;tar -zxvf mha4mysql-node-0.56.tar.gz;cd mha4mysql-node-0.56;perl Makefile.PL;make && make install;" 
#    ssh $ip "cd /mysql/mha/install;tar -zxvf mha4mysql-manager-0.56.tar.gz;cd mha4mysql-manager-0.56;perl Makefile.PL;make && make install;"
  done
}

#install_rpm

delete_other_vip()
{
  host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
  VIP=`ip a| grep -w inet | grep -v $host | grep -v "127.0.0.1" | grep -v brd | awk '{print $2}' | awk -F'/' '{print $1}'`
  if [ "$VIP" == "" ]
  then
    echo "`date` - [info] There is no vip exists...so there is no need to delete vip..."
  else
    n=`echo "$VIP"|wc -l`
    echo "`date` - [info] the number of vips is: $n"
    for((i=1;i<=$n;i++))
    do
      vip=`echo "$VIP" | awk -v line=$i 'NR==line{print $0}'`
      echo "`date` - [info] Begin to delete the VIP:$vip"
      interface='eth0'
      ip addr del $vip/32 dev $interface
    done
  fi
}

check_start_mha()
{ 
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  delete_other_vip
  virtual_ip=`get_vip`
  virtual_ip=`echo "$virtual_ip" | awk 'NR==2{print $0}'`
  ssh $master_ip "ip addr add $virtual_ip/32 dev eth0"
  ip=`cat ./ip_pass.txt | awk -F' ' 'NR==2{print $1}'`
  ssh $ip "masterha_check_ssh --conf=/mysql/mha/conf/mha.conf"
  ssh $ip "masterha_check_repl --conf=/mysql/mha/conf/mha.conf"
  ssh $ip "nohup masterha_manager --conf=/mysql/mha/conf/mha.conf > /mysql/mha/log/manager.log  < /dev/null 2>&1 &" 
}
#check_start_mha


auto_mha()
{ 
  my_usage
  echo "================================================================================================="
  echo "`date` - [info] begin to install mha automatically!"
  echo
  echo
  echo
  echo "============================================Auto SSH============================================="
  echo "`date` - [info] The first Step is to achieve auto_ssh..."
  auto_ssh
  echo "========================================Set SSH Finished========================================="
  echo
  echo
  echo
  echo "==========================================Set Replication========================================"
  echo "`date` - [info] The Second Step is to finish Setting Replication Between MySQL Instances"
  set_replication
  echo "=======================================Set Replicatoin Finished=================================="
  echo
  echo
  echo
  echo "=======================================Set Semi_Replication======================================"
  echo "`date` - [info] The Third Step is to finish Setting Semi_replication..."
  set_semi_repl
  echo "====================================Set Semi_Replication Finished================================"
  echo
  echo
  echo
  echo "========================================Create MHA Directory====================================="
  echo "`date` - [info] The Forth Step is to Create MHA Directory..."
  create_mhadir
  echo "================================Create MHA Directory Finished===================================="
  echo
  echo
  echo
  echo "=========================================Get MHA Need Files======================================"
  echo "`date` - [info] The Fifth Step is to Get MHA Need Files..."
  get_rpm_cnf_scripts_file
  echo "====================================Get MHA Need Files Finished=================================="
  echo
  echo
  echo
  echo "============================================Install RPM=========================================="
  echo "`date` - [info] The Sixth Step is to Install Needing RPM Files..."
  install_rpm
  echo "========================================Install RPM Finished====================================="
  echo
  echo
  echo
  echo "======================================Check And Start MHA Manager================================"
  echo "`date` - [info] The Seventh Step is to Check And Start MHA Manager..."
  check_start_mha
  echo "===============================Check And Start MHA Manager Finished=============================="
  echo
  echo
  echo
  echo "`date` - [info] Install MHA automatically successfully!"
}
auto_mha
