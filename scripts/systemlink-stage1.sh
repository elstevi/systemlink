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
fetch 
echo "[DONE]"
