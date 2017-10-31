#!/bin/sh

if [ "$1" != "nochecks" ]; then
	# Check ping
	printf "Pinging google..."
	ping -c 1 8.8.8.8 > /dev/null
	if [ "$?" != "0" ]; then
		echo "It doesn't seem like we are connected to the internet, couldn't ping google!"
		exit 
	fi
	echo "[DONE]"

	# Check DNS
	printf "Attempting host lookup..."
	host google.com > /dev/null
	if [ "$?" != "0" ]; then
		echo "Unable to do DNS lookups"
	fi
	echo "[DONE]"
fi
# Get stage 2 script
printf "Downloading stage 2 script"
case `uname` in
	FreeBSD)
		fetch -q -o "/tmp/systemlink-stage2.sh" "https://raw.githubusercontent.com/elstevi/systemlink/master/scripts/systemlink-stage2.sh"
	;;
	Linux)
		wget --quiet -O "/tmp/systemlink-stage2.sh" "https://raw.githubusercontent.com/elstevi/systemlink/master/scripts/systemlink-stage2.sh"
	;;


esac
echo "[DONE]"

echo "Executing stage 2 script, goodbye."
while true; do
	/bin/sh "/tmp/systemlink-stage2.sh"
	if [ "$?" == "0" ]; then
		break
	fi
done

