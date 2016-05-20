#!/bin/bash

echo "Starting up!"

mysqlstop()
{
#Stop MySQL if started
echo "Stopping MySQL..."
if ! service mysql stop; then
	exit 1
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

dircreate()
{
#Creating backup directory in /root/
echo "Creating initial backup directory..."
if [ ! -d /root/innodbrepair ]; then
	mkdir -p /root/innodbrepair/
else
	echo "Cannot Create Directory"
	exit 1
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

ibdatabackup()
{
#Back up all innodb stuff
echo "Backing up innodb files..."
if cd /var/lib/mysql/; then
	dd if=ibdata1 of=ibdata1.bak conv=noerror
	rsync -avhP ibdata* ib_log* /root/innodbrepair/
	cd /root/innodbrepair/
else
	echo "Cannot backup data"
	exit 1
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

startinrecovery()
{
#Put MySQL in recovery
echo "Putting MySQL in innodb forced recovery mode 3..."
if ! grep -q innodb_force_recovery /etc/my.cnf; then
	echo "innodb_force_recovery=3" >> /etc/my.cnf
	sed -i '/innodb_purge_threads/s/=[0-9]*/=0/' /etc/my.cnf
	echo -e '\E[32m'"\033[1mDONE\033[0m"
else
	echo "Already in recovery mode"
fi

#start mysql and tail the log for errors
echo "Starting up MySQL..."
if ! service mysql start; then
	echo "Can't Start MySQL. Check error log"
	exit 1
else
	tail -100 /var/lib/mysql/`hostname`.err > mysql.error
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

checkmysql()
{
#Run a MySQL check for MySIAM
echo "Running MySIAM check and repair"
mysqlcheck -A -r
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

dumpdbs()
{
#Dump all databases to .sql files
echo "Dumping Databases..."
echo "Backing up default MySQL first"
mysqldump mysql > mysql.sql
echo -e '\E[32m'"\033[1mDONE\033[0m"
echo "Backing up user Databases..."
mysql -Nse 'show databases' | egrep -v "information_schema|cphulkd|eximstats|leechprotect|logaholicDB_cent6base_cpanel|modsec|mysql|performance_schema|test|whmxfer|roundcube" > dblist.txt
for i in $(cat dblist.txt); do 
	echo "Trying to dump $i"
	count=1
	until mysqldump $i > $i.sql; do 
	sleep 5 
	((count++))
	if [ $count -eq 5 ]; then  
		printf "Reached max amount of tries, moving on...\n" 
		break 
	fi
	done 
done
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

deleteibdata()
{
#Delete innodb data
echo "Removing Innodb Data..."
rm -f /var/lib/mysql/ib*
rm -rf /var/lib/mysql/roundcube/
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

restartmysql()
{
#Restart MySQL to rebuild Innodb log files
echo "Removing forced recovery mode and rebuilding ibdata and ib_logfiles..."
if grep -q "innodb_force_recovery" /etc/my.cnf; then
	sed -i '/innodb_purge_threads/s/=[0-9]*/=1/' /etc/my.cnf
	sed -i 's/innodb_force_recovery=3//' /etc/my.cnf
fi

if ! service mysql restart; then
	echo "Can't Start MySQL. Check error log"
	exit 1
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

importdbs()
{
#Get list of dbs to import
echo "Re-Importing Innodb Databases..."
mysqlcheck -A | grep "doesn't exist" | cut -d'.' -f1 | sort | uniq | sed "s/Error    : Table '//" > innodbs.txt
for i in $(cat innodbs.txt); do 
	echo $i 
	rm -f /var/lib/mysql/$i/* 
	mysql $i < $i.sql 
done
/usr/local/cpanel/bin/update-roundcube --force
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

mysqlrestart()
{
#One last MySQL Restart
echo "One last MySQL restart..."
if ! service mysql restart; then
	echo "You broke something"
fi
echo -e '\E[32m'"\033[1mDONE\033[0m"
}

confirm () {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case $response in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

confirm "Stop MySQL?" && mysqlstop
confirm "Create Backup Directory?" && dircreate
confirm "Backup Innodb Files?" && ibdatabackup
confirm "Start MySQL in recovery?" && startinrecovery
confirm "Check MySQL?" && checkmysql
confirm "Dump user databases?" && dumpdbs
confirm "Delete Innodb data to proceed with recovery?" && deleteibdata
confirm "Take MySQL out of Recovery to rebuild ibdata and ib_logfiles?" && restartmysql
confirm "Import MySQL databases?" && importdbs
confirm "Final MySQL restart?" && mysqlrestart