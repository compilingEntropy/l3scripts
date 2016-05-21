#!/bin/bash

shared_regex='\b(box|host|fast|just|hgsg|rs[bj])[0-9]{2,4}\b'
rm -f ./SCANNED

params=( $( for arg in $@; do echo "$arg"; done ) )
for arg in ${params[@]}; do
	if [[ "$arg" =~ $shared_regex ]]; then
		shared=( ${shared[@]} "$arg" )
	fi
done
if (( ${#shared[@]} == 0 )); then
	curl -Ss https://snowrealm.info/bh/abuse/ > ./abuse.out
	#abuse.out is the result of travis' script
	shared=( $( egrep -o "$shared_regex" ./abuse.out | sort -u ) )
	#shared=( $( awk -F'[\t\.]' '/\t(box|host|fast|just|hgsg)/ {print $6}' ./abuse.out | sort -u ) )
fi
if (( ${#shared[@]} == 0 )); then
	echo "No boxes found to be scanned."
	exit 0
fi

####
# the scripts to be run on shared
IFS='' read -r -d '' shared_script_stage <<-'ENDSSH'
	cat > ./find_hacked.sh <<-'ENDSCRIPT'
		#!/bin/bash

		if [[ "$(whoami)" != "root" ]]; then
			echo "Please run this as root."
			exit 1
		fi

		bad_crons=( $( egrep "(/var/tmp|1\.sh)" /var/log/cron | awk '{print $6}' | sed -rn "s|.*\(([[:alnum:]]{8})\)|\1|p" | sort -u ) )
		for user in ${bad_crons[@]}; do
			echo "$user" >> ./suspicious_users
		done

		echo -n "finding..."
		for i in {1..10}; do
			echo -n '.'
			sleep 1
			ps aux | awk '{if ( $1 !~ /(^[0-9]+$|^USER$)/ ) print }' | egrep -v "(dovecot|mailnull|postgres|sshd|pts|fcgiphp5|spamd|index.php|defunct|wp-cron.php|ftpd|cpanel|whostmgrd|webmaild|bash|wp-login.php|root|dbus|nscd|_lldpd|ntp|zabbix|mysql|nobody|USER)" | awk '{ print $1 }' | sort -u >> ./suspicious_users
		done

		for domain in $( grep "550-Verification failed for" /var/log/domlogs/error_log | awk '{print $12}' | sed -r 's|^.*@([^>]+)>[,]?$|\1|g' | sort -u ); do
			echo "$( /scripts/whoowns "$domain" )" >> ./suspicious_users
		done

		echo
		suspicious_users=( "$( cat ./suspicious_users | sort -u )" )
		rm -f ./suspicious_users

		for user in ${suspicious_users[@]}; do
			if [[ -f ./clean ]] && [ "$( grep -c "$user" ./clean )" -ge 1 ]; then
				suspicious_users=( ${suspicious_users[@]/$user/} )
				echo "$user"
				echo "Already scanned, was found to be clean."
			fi
		done

		scan()
		{
			/bin/su -l -s /bin/bash "$user" >> ./"${user}_malware.txt" <<-'EOF'
				find2perl ~/public_html -type f -type f \( -iname '*.php' -o -iname 'libworker*' \) -print0 | perl | xargs -0 -I{} egrep -Hli '\@\$GLOBALS.*continue|GLOBALS.*x61|FbU73jxn|IGlmICgg|x77.x69.x76|vd56b6998|filesman|bar\/index|client.*x05.x01|img.*empty.*referrer|wiahsuidhaudh|bvkwn52|="base64_decode"|eval.base64_decode' "{}"
			EOF
		}

		for user in ${suspicious_users[@]}; do
			echo "$user"

			if [[ ! -f ./"${user}_malware.txt" ]]; then
				touch ./"${user}_malware.txt"
			
				tail -f ./"${user}_malware.txt" &
				pid="$!"

				if grep -q 'SPECIAL_SUSPEND=1' /var/cpanel/users/"$user"; then
					echo "== USER ALREADY SUSPENDED ==" > ./"${user}_malware.txt"
				fi

				if [[ " ${bad_crons[@]} " =~ " $user " ]]; then
					crontab -l -u "$user" >> ./"${user}_malware.txt"
					echo '' >> ./"${user}_malware.txt"
				fi

				scan
				while [ $? -eq 2 ]; do
					echo "Retrying..."
					scan
				done

				kill "$pid"
				wait "$pid" 2> /dev/null

				#false positives
				sed -i '/com_admin\/script.php$/d' ./"${user}_malware.txt"
				sed -i '/backupbuddy\/_repairbuddy.php$/d' ./"${user}_malware.txt"
				sed -i '/private_files\/block_private_files.php$/d' ./"${user}_malware.txt"
				sed -r -i '/lang\/.{1,6}\/(moodle.php|core.php)$/d' ./"${user}_malware.txt"
				sed -i '/mahara\/lib.php$/d' ./"${user}_malware.txt"
				sed -i '/moodle\/user\/files.php$/d' ./"${user}_malware.txt"
				sed -i '/tests\/validator_test.php$/d' ./"${user}_malware.txt"
				sed -i '/libs\/factory\/core\/includes\/plugin.class.php$/d' ./"${user}_malware.txt"
				sed -r -i '/com_jmap\/controllers\/(metainfo.php|sources.php)$/d' ./"${user}_malware.txt"
				sed -r -i '/protected\/controllers\/(FrontController.php|Controller.php)$/d' ./"${user}_malware.txt"

				if [[ ! -s ./"${user}_malware.txt" ]]; then
					echo "No malware found."
					rm ./"${user}_malware.txt"
					echo "$user" >> ./clean
				fi
			else
				echo "Already found this one."
			fi

		done
	ENDSCRIPT

	cat > ./top.sh <<-'ENDSCRIPT'
		#!/bin/bash
		while [[ ! -f ./PID ]]; do
			sleep 1
		done
		pid="$( cat ./PID )"
		while ps -p "$pid" &> /dev/null; do
			top -n 5 -c
		done
	ENDSCRIPT
ENDSSH
IFS='' read -r -d '' shared_script_run <<-'ENDSSH'
	chmod u+x ./find_hacked.sh ./top.sh
	sudo ./find_hacked.sh &
	echo $! > ./PID
	wait
	rm ./PID ./find_hacked.sh ./top.sh
ENDSSH
#
####

for box in ${shared[@]}; do
	echo "$box" >> ./SCANNED
	printf '\033]2;%s\007' "$box"
	echo "Connecting to $box"
	ssh "$box" "${shared_script_stage}"
	xfce4-terminal -T "$box" -e "ssh -t "$box" 'sudo ./top.sh; exit'; exit" &
	ssh -t "$box" "${shared_script_run}"
	wait
done
