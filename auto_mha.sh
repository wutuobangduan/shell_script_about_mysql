#!/bin/bash
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
      echo "continue another host!"
    else
      ssh root@$ip "/mysql/mha/auto.sh"
    fi
  done
}
set_replication()
{
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "current ip is : $ip"
    grant_rep=`ssh $ip su - mysqldp <<!
    mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "grant replication slave on *.* to rep@'%' identified by 'rep'"
    exit
!`
    echo "grant rep is $?"
    grant_rep=$?
    grant_admin=`ssh $ip su - mysqldp <<!
    mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "grant all privileges  on *.* to admin@'%' identified by 'admin'"
    exit
!`
    echo "grant admin is $?"
    grant_admin=$?
    if [ $grant_rep -eq 0 -a $grant_admin -eq 0 ]
    then
       echo "grant successfull!"
    else
       echo "grant failed"
    fi
    if [ $i == 1 ]
    then
      master_ip=$ip
      master_port=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "select @@port"
      exit
!`
      master_port=`echo $master_port | awk -F' ' '{print $2}'`
      echo "master port is : $master_port"
      master_log_file=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show master status\G"| awk -F':' 'NR==2{print $2}'
      exit
!`
      #master_log_file=`mysql -uadmin -padmin -h$ip -P$master_port -e "show master status\G" | awk -F':' 'NR==2{print $2}'`
      master_log_file=`echo $master_log_file|awk -F':' '{print $2}' | sed 's/^ //'`
      echo "master_log_file is : $master_log_file"
      master_log_pos=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show master status\G"| awk -F':' 'NR==3{print $2}' | sed 's/^ //'
      exit
!`
      master_log_pos=`echo $master_log_pos|awk -F':' '{print $2}' | sed 's/^ //'`
      echo "master_log_pos is : $master_log_pos"
    else
      echo "$ip is a slave!"
      stop_slave=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "stop slave"
      exit
!`
      stop_slave=$?
      if [ $stop_slave -eq 0 ]
      then
         echo "stop slave successfull"
      else
         echo "stop slave failed,exit!!"
         exit
      fi
      change_master=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "change master to master_host='$master_ip',master_port=$master_port,master_user='rep',master_password='rep',master_log_file='$master_log_file',master_log_pos=$master_log_pos"
      exit
!`
      change_master=$?
      if [ $change_master -eq 0 ]
      then
        echo "change master successfull"
      else
        echo "change master failed,exit!!"
        exit
      fi
      start_slave=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "start slave"
      exit
!`
      start_slave=$?
      if [ $start_slave -eq 0 ]
      then
        echo "start slave successfull"
      else 
        echo "start slave failed,exit!!"
        exit
      fi
      slave_io_running=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show slave status\G"|grep 'Slave_IO_Running'
      exit
!`
      slave_io_running=`echo $slave_io_running |awk -F':' '{print $2}'|sed 's/^ //'`
      echo "slave io state is $slave_io_running"
      slave_sql_running=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show slave status\G"|grep -w 'Slave_SQL_Running'
      exit
!`
      slave_sql_running=`echo $slave_sql_running |awk -F':' '{print $2}'|sed 's/^ //'`
      echo "slave sql state is $slave_sql_running"
      if [ "$slave_io_running" = "Yes" -a "$slave_sql_running" = "Yes" ]
      then
        echo "set replication success!!!continue"
      else
        echo "set replication failed!!!exit"
        exit
      fi
    fi
    
  done
}
auto_ssh
set_replication
set_semi_repl()
{
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "current ip is : $ip"
    check_master_semi=`ssh $ip su - mysqldp <<!
    mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show plugins\G" | grep "semisync_master.so"
    exit
!`
    echo "check master semi result is : $check_master_semi"
    check_slave_semi=`ssh $ip su - mysqldp <<!
    mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "show plugins\G" | grep "semisync_slave.so"
    exit
!`
    echo "check slave semi result is : $check_slave_semi"
    if [ "$check_master_semi" = "" -a "$check_slave_semi" = "" ]
    then
      set_semi=`ssh $ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "install plugin rpl_semi_sync_master soname 'semisync_master.so';set global rpl_semi_sync_master_enabled=1;set global rpl_semi_sync_master_timeout=1000;install plugin rpl_semi_sync_slave soname 'semisync_slave.so';set global rpl_semi_sync_slave_enabled=1;"
      exit
!`
      if [ $? -eq 0 ]
      then 
        echo "set semi replication successufull!"
      else 
        echo "set semi replication failed"
      fi
    else
      echo "There is no need to install semi sync plugin!"
    fi
    modify_my_configure=`ssh $ip su - mysqldp <<!
    sed -i '/rpl_semi/d' ~/etc/my.cnf
    sed -i '/^query_cache_type/a\rpl_semi_sync_master_enabled=1\nrpl_semi_sync_master_timeout=1000\nrpl_semi_sync_slave_enabled=1' ~/etc/my.cnf
    exit
!`
    if [ $? = 0 ]
    then
      echo "On $ip,modify my.cnf successfully!"
    else
      echo "on $ip,modify my.cnf failed!"
      echo "Please check the script!!!"
    fi
  done
}
set_semi_repl

get_master_port()
{
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_port=`ssh $master_ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "select @@port"
      exit
!`
  master_port=`echo $master_port | awk -F' ' '{print $2}'`
  echo $master_port
}
get_master_port

get_master_binlogdir()
{
  master_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==1{print $1}'`
  master_binlog_full_dir=`ssh $master_ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "select @@log_bin_basename"
      exit
!`
  master_binlog_full_dir=`echo $master_binlog_full_dir | awk -F' ' '{print $2}'`
  master_binlog_dir=`dirname $master_binlog_full_dir`
  echo $master_binlog_dir
}

get_master_binlogdir

get_slave_port()
{
  slave_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==2{print $1}'`
  slave_port=`ssh $slave_ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "select @@port"
      exit
!`
  slave_port=`echo $slave_port | awk -F' ' '{print $2}'`
  echo $slave_port
}
get_slave_port

get_slave_binlogdir()
{
  slave_ip=`cat ./ip_pass.txt | awk -F' ' 'NR==2{print $1}'`
  slave_binlog_full_dir=`ssh $slave_ip su - mysqldp <<!
      mysql -uroot -S /mysql/mysqldp/data/mysql.sock -e "select @@log_bin_basename"
      exit
!`
  slave_binlog_full_dir=`echo $slave_binlog_full_dir | awk -F' ' '{print $2}'`
  slave_binlog_dir=`dirname $slave_binlog_full_dir`
  echo $slave_binlog_dir
}

get_slave_binlogdir

LOG=./auto_mha.log
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
    echo "current ip is : $ip"
    ssh $ip "[[ -d /mysql/mha/conf ]] && echo 'on $ip configuration dir exits,continue'|| mkdir -p /mysql/mha/conf"
    ssh $ip "[[ -d /mysql/mha/log ]] && echo 'on $ip log dir exits,continue'|| mkdir -p /mysql/mha/log"
    ssh $ip "[[ -d /mysql/mha/install ]] && echo 'on $ip install dir exits,continue'|| mkdir -p /mysql/mha/install"
    ssh $ip "[[ -d /mysql/mha/scripts ]] && echo 'on $ip scripts dir exits,continue'|| mkdir -p /mysql/mha/scripts"
  done
}

create_mhadir

get_rpm_cnf_scripts_file()
{ 
  scp_ip=`cat ./scp_ip_pass.txt | awk -F' ' '{print $1}'`
  scp_pass=`cat ./scp_ip_pass.txt | awk -F' ' '{print $2}'`
  ./autoscp.exp $scp_ip $scp_pass
  chmod +x /mysql/mha/scripts/master_ip_online_change
  chmod +x /mysql/mha/scripts/master_ip_failover
  host=`ifconfig | grep 'inet addr' | head -1 | awk -F':' '{print $2}' | tr -d "[a-z][A-Z][ ]"`
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | grep -v $host | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "current ip is : $ip"
    if [ "$ip" = "" ]
    then 
      echo "conitune anoter ip to get files!"
    else
      scp /mysql/mha/conf/* root@$ip:/mysql/mha/conf/
      scp /mysql/mha/install/* root@$ip:/mysql/mha/install/
      scp /mysql/mha/scripts/* root@$ip:/mysql/mha/scripts/
    chmod_x=`ssh $ip "chmod +x /mysql/mha/scripts/master_ip_online_change;chmod +x /mysql/mha/scripts/master_ip_failover"`
    if [ $? = 0 ]
    then
      echo "chmod +x successfully!"
    else
      echo "chmod +x failed!"
    fi
    fi
  done
}
get_rpm_cnf_scripts_file

#install_rpm()
#{  
#  n=`cat ./ip_pass.txt | wc -l`
#  for((i=1;i<=$n;i++))
#  do
#    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
##    echo "current ip is : $ip"
#    
#    ssh $ip "rpm -ivh /mysql/mha/install/Percona-Server-shared-55-5.5.18-rel23.0.203.rhel.x86_64.rpm;rpm -ivh /mysql/mha/install/Percona-Server-client-55-5.5.18-rel23.0.203.rhel.x86_64.rpm;rpm -ivh /mysql/mha/install/MySQL-shared-compat-5.5.35-1.el6.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-Config-Tiny-2.12-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Email-Date-Format-1.002-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Mail-Sender-0.8.16-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Mail-Sendmail-0.79-1.2.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-MIME-Lite-3.029-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Module-Runtime-0.012-1.el6.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Parallel-ForkManager-0.7.5-2.2.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Sys-Syslog-0.27-1.el6.rf.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-TimeDate-1.20-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Try-Tiny-0.09-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Test-Pod-1.45-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Module-Implementation-0.06-1.el6.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Params-Validate-0.95-1.el6.rfx.x86_64.rpm;rpm -ivh /mysql/mha/install/perl-MailTools-2.12-1.el6.rfx.noarch.rpm;rpm -ivh /mysql/mha/install/perl-Log-Dispatch-2.26-1.el6.rf.noarch.rpm;rpm -ivh /mysql/mha/install/perl-DBD-MySQL-4.022-1.el6.rfx.x86_64.rpm;" >>$LOG 2>&1
#    ssh $ip "cd /mysql/mha/install;tar -zxvf mha4mysql-node-0.56.tar.gz;cd mha4mysql-node-0.56;perl Makefile.PL;make && make install;" >>$LOG 2>&1
#    ssh $ip "cd /mysql/mha/install;tar -zxvf mha4mysql-manager-0.56.tar.gz;cd mha4mysql-manager-0.56;perl Makefile.PL;make && make install;" >>$LOG 2>&1
#  done
#}

#install_rpm

install_mha_rpm()
{
  n=`cat ./ip_pass.txt | wc -l`
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    echo "current ip is : $ip"
    if [ -f /etc/yum.repos.d/mha.repo ]
    then 
      echo "mha.repo exists,continue"
    else
      touch /etc/yum.repos.d/mha.repo
    fi
    ssh $ip cat /dev/null >/etc/yum.repos.d/mha.repo
    ssh $ip echo "[yum-suningmysql]" >> /etc/yum.repos.d/mha.repo
    ssh $ip echo "name=mha rpm" >>/etc/yum.repos.d/mha.repo
    ssh $ip echo "baseurl=http://10.27.81.9/yum/" >>/etc/yum.repos.d/mha.repo
    ssh $ip echo "gpgcheck=0" >>/etc/yum.repos.d/mha.repo
    ssh $ip echo "enabled=1" >>/etc/yum.repos.d/mha.repo
    echo "on $ip,check repolist..."
    ssh $ip yum repolist
    if [ $i = 2 ]
    then
      echo "on $ip,install mha manager..."
      ssh $ip yum -y install mha4mysql-manager*
    else
      echo "on $ip,install mha node..."
      ssh $ip yum -y install mha4mysql-node*
    fi
  done
}

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
  for((i=1;i<=$n;i++))
  do
    ip=`cat ./ip_pass.txt | awk -F' ' -v line=$i 'NR==line{print $1}'`
    if [ $i = 1 ]
    then 
      sed -i "/hostname=.*/{x;s/^/./;/^\.\{1\}$/{x;s/.*/hostname=$ip/;x};x;}" conf/mha.conf
      sed -i "/port=.*/{x;s/^/./;/^\.\{1\}$/{x;s/.*/port=`get_master_port`/;x};x;}" conf/mha.conf
      sed -i "/master_binlog_dir=.*/{x;s/^/./;/^\.\{2\}$/{x;s,.*,master_binlog_dir=`get_master_binlogdir`,;x};x;}" conf/mha.conf
      sed -i "/remote_workdir=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/remote_workdir=\/mysql\/mha\/log/;x};x;}" conf/mha.conf
    elif [ $i = 2 ]
    then
      sed -i "/hostname=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/hostname=$ip/;x};x;}" conf/mha.conf
      sed -i "/port=.*/{x;s/^/./;/^\.\{2\}$/{x;s/.*/port=`get_slave_port`/;x};x;}" conf/mha.conf
      sed -i "/master_binlog_dir=.*/{x;s/^/./;/^\.\{3\}$/{x;s,.*,master_binlog_dir=`get_slave_binlogdir`,;x};x;}" conf/mha.conf
      sed -i "/remote_workdir=.*/{x;s/^/./;/^\.\{3\}$/{x;s/.*/remote_workdir=\/mysql\/mha\/log/;x};x;}" conf/mha.conf  
    fi
  done
}

configure_mha
