#not really optimized, but meh
#generates another script, tar_resold.sh, which should be run as root and probably niced
read -p "Reseller: " reseller
echo "mkdir \"/home/${reseller}/resold_backups/\"" > ./tar_resold.sh
for user in $( cat ./usernames | sort -u ); do
	echo "$user"
	unset path
	path="$( sudo ls /backup{1..8}{,.old}/{archived-backups,cpbackup}/daily/"$user"/lastgenerated 2>/dev/null )"
	path="${path%/*}/"
	echo
	if [[ -d "$path" ]]
		then echo "tar czvf /home/"$reseller"/resold_backups/"$user".tar.gz "$path"" >> ./tar_resold.sh
	fi
done
chmod u+x ./tar_resold.sh
sed -i '/ \/$/d' ./tar_resold.sh
echo "chown -R "$reseller":"$reseller" /home/"$reseller"/resold_backups/" >> ./tar_resold.sh
cat ./tar_resold.sh
echo "Users not found:"; for user in $( cat ./usernames ); do if ! grep -q "$user" ./tar_resold.sh; then echo "$user"; fi; done
