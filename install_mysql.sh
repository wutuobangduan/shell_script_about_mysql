#!/bin/sh

UNIXGREP=grep

MYNAME=`basename $0`
my_usage()
{
	cat <<EOF 
Usage:${MYNAME} [options]
Valid options are:
  -h			help, Display this message
  -D datadir	mysql data directory
EOF
}

my_log()
{
	echo "$1" 2>&1 | tee -a $LOG
}

modify_my_cnf()
{
	_user_profile=$HOME/etc/my.cnf
	processed=0
	> ${_user_profile}
	while read inputline
	do
		if [ $processed -eq 2 ]
		then
			echo "${inputline}" >> ${_user_profile}
			continue
		fi
		if echo $inputline | ${UNIXGREP} -q basedir 
		then
			#echo "${inputline}" |sed -e's/[\011 ]*\(.*= *\)[^ ]*\(.*\)/\1/'
			echo "${inputline}" |sed -e "s,\(.*= *\)[^ ]*\(.*\),\1${HOME}\2," >> ${_user_profile}
		elif echo $inputline | ${UNIXGREP} -q datadir
		then
			processed=1
			echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${mysql_data_dir}"'\2,' >> ${_user_profile}
		elif echo $inputline | ${UNIXGREP} -q tmpdir
		then
			processed=2
			echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${mysql_data_dir}"'\2,' >> ${_user_profile}
		elif echo $inputline | ${UNIXGREP} -q socket
		then
			echo "${inputline}" |sed -e 's,\(.*= *\)[^ ]*\(.*\),\1'"${mysql_data_dir}"/mysql.sock'\2,' >> ${_user_profile}
		else
			echo "${inputline}" >> ${_user_profile}
		fi
	done < ./my.cnf
}

LOG=./install_mysql.log

>$LOG
[ -d $HOME/etc ] || mkdir $HOME/etc 2>&1 | tee -a $LOG
[ -d $HOME/log ] || mkdir $HOME/log 2>&1 | tee -a $LOG

mysql_data_dir=
while getopts "D:h" opt
do
    case $opt in
	D) mysql_data_dir=$OPTARG;;
	h) my_usage;return 0;;
    *) my_usage;return 1;;
    esac
done

if [ "${mysql_data_dir}" = "" ] 
then
	read -p "Please input mysql data directory [absolute path]: " mysql_data_dir
fi

[ "${mysql_data_dir}" = "" ] && { my_log "mysql data directory can not be empty. please check!";exit 1; }
tmp=`dirname ${mysql_data_dir}`

if [ "$tmp" = "" -o ${tmp:0:1} != '/' ]
then
	mysql_data_dir=`pwd`/`basename ${mysql_data_dir}`
fi

if [ -d ${mysql_data_dir} ]
then
	[ -w ${mysql_data_dir} ] || { my_log "\"${mysql_data_dir}\" does not exist or have not write permissions. please check!";exit 1; }
else
	mkdir -p ${mysql_data_dir}
	if [ $? -eq 0 ]
	then
		my_log "create \"${mysql_data_dir}\" successfully!"
	else
		my_log "can not create \"${mysql_data_dir}\"!"
	fi
fi

# unzip
my_log "unzip ..."
unzip -u Percona-Server-5.5.18-rel23.0-203.Linux.x86_64.zip

# install
my_log "installing version ..."
tar -xzvpf ./Percona-Server-5.5.18-rel23.0-203.Linux.x86_64.tar.gz > /dev/null 2>&1
cp -Rf ./Percona-Server-5.5.18-rel23.0-203.Linux.x86_64/* ~  2>&1 | tee -a $LOG
rm -rf ./Percona-Server-5.5.18-rel23.0-203.Linux.x86_64  2>&1 | tee -a $LOG

# modify my.cnf
modify_my_cnf

#cp -f ./my.cnf ~/etc  2>&1 | tee -a $LOG
chmod +x ./mysqld_safe
cp -f ./mysqld_safe ~/bin  2>&1 | tee -a $LOG

tar -xzvpf ./percona-xtrabackup-2.1.3-608.tar.gz > /dev/null 2>&1
cp -Rf ./percona-xtrabackup-2.1.3/* ~  2>&1 | tee -a $LOG
rm -rf ./percona-xtrabackup-2.1.3

cp -f ./mysql.server ~/bin
chmod +x ~/bin/mysql.server
rm -f ./mysql.server

# install system tables
my_log "install system tables ..."
$HOME/scripts/mysql_install_db --defaults-file=$HOME/etc/my.cnf --user=${LOGNAME} --basedir=$HOME --datadir=${mysql_data_dir}  >> $LOG 2>&1

# modify environment variables
if [ -f $HOME/.bash_profile ]
then
	_user_profile=$HOME/.bash_profile
	( ${UNIXGREP} PATH ${_user_profile} | ${UNIXGREP} -q '^\$HOME/bin' ) || \
        echo "export PATH=\$HOME/bin:\$PATH">>${_user_profile}
    ( ${UNIXGREP} LD_LIBRARY_PATH ${_user_profile} | ${UNIXGREP} -q '^\$HOME/lib' ) || \
        echo "export LD_LIBRARY_PATH=\$HOME/lib:\$LD_LIBRARY_PATH">>${_user_profile}
fi

echo "install successfully!" | tee -a $LOG
