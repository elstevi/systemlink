#!/bin/sh

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

# Check out stage two script
printf "Downloading stage 2 script"
fetch -q -o "/tmp/systemlink-stage2.sh" "https://raw.githubusercontent.com/elstevi/systemlink/master/scripts/systemlink-stage2.sh"
echo "[DONE]"

echo "Executing stage 2 script, goodbye."
while true; do
	/bin/sh "/tmp/systemlink-stage2.sh"
	if [ "$?" == "0" ]; then
		break
	fi
done

