#!/bin/sh
set -x

BACK_TITLE="Halo 2 System Link Network"
OS=`uname`
REMOTE_BRIDGE="10.4.7.12"
USER=`whoami`

# Mark a binary as required. If called and the binary doesn't exist, the program will fail and exit
binary_requirement () {
	BINARY=$1
	$BINARY > /dev/null 2>&1
	# If running the binary results in a return code of 127, it doesn't exist
	if [ "${?}" == "127" ]; then
		echo "Could not find ${BINARY} on your system. It is required to use this program. Please install ${BINARY}"
		exit
	fi	
}

# Cleans up bridges, taps and pids that have been left behind by previous runs of this script
cleanup () {
	printf "Cleaning up old taps, bridges, and pids..."

	# Iterate over running ssh and autossh pids, and kill them
	for PID in `ps auxww | grep autossh | grep -v grep | awk '{print $2}'` `ps auxww | grep ssh | grep Stric | awk '{print $2}'`; do
		${SUDO} kill -9 ${PID}
	done
	
	# Destroy the tap
	${TAP_DESTROY_COMMAND}

	# Destroy the bridge
	if [ "${OS}" == "Linux" ]; then
		${SUDO} ifconfig br0 down
	fi
	${BRIDGE_DESTROY_COMMAND}

	echo '[DONE]'
}

# If we aren't root, we are going to need to sudo some commands
if [ "${USER}" != "root" ]; then
	SUDO="sudo"
	echo "Since we aren't root, we need to use sudo. You may be asked for your local user's password below."
else
	SUDO=""
fi

binary_requirement 'base64 --version'
RAND_USER=`dd bs=1 count=10 if=/dev/urandom | base64 | tr -d \+ | tr -d \/ | tr -d \=`

# There are operating specific commands, define them here.
case "$OS" in
	FreeBSD)
		# Set a sysctl so unprivileged FreeBSD users can open the tap device
		${SUDO} sysctl net.link.tap.user_open=1

		# Tap commands
		TAP="tap0"
		TAP_NUM="0"
		TAP_PATH="/dev/${TAP}"
		TAP_CREATE_COMMAND="${SUDO} ifconfig ${TAP} create"
		TAP_DESTROY_COMMAND="${SUDO} ifconfig ${TAP} destroy"
		TAP_UP_COMMAND="${SUDO} ifconfig ${TAP} up"
		
		# Bridge commands	
		BRIDGE="bridge0"
		BRIDGE_CREATE_COMMAND="${SUDO} ifconfig ${BRIDGE} create"
		BRIDGE_DESTROY_COMMAND="${SUDO} ifconfig ${BRIDGE} destroy"
		BRIDGE_UP_COMMAND="${SUDO} ifconfig ${BRIDGE} up"
		BRIDGE_JOIN_COMMAND="${SUDO} ifconfig ${BRIDGE} addm ${TAP}"
		FETCH_CONNECT="fetch -q -o - https://systemlink.douglas-enterprises.com/join/${RAND_USER}"

		;;
	Linux)
		BRIDGE="br0"
		TAP="tap0"
		TAP_NUM="0"

		TAP_CREATE_COMMAND="${SUDO} ip tuntap add ${TAP} mode tap"
		TAP_DESTROY_COMMAND="${SUDO} ip tuntap del ${TAP} mode tap"
		TAP_UP_COMMAND="${SUDO} ifconfig ${TAP} up"

		BRIDGE_CREATE_COMMAND="${SUDO} brctl addbr ${BRIDGE}"
		BRIDGE_DESTROY_COMMAND="${SUDO} brctl delbr ${BRIDGE}"
		BRIDGE_UP_COMMAND="${SUDO} ifconfig ${BRIDGE} up"

		BRIDGE_JOIN_COMMAND="${SUDO} brctl addif ${BRIDGE} ${TAP}"
		FETCH_CONNECT="wget --quiet -O - https://systemlink.douglas-enterprises.com/join/${RAND_USER}"
		binary_requirement ip
		binary_requirement brctl
	esac

# Make sure everything we need exists on this system
binary_requirement autossh
binary_requirement dialog

# Cleanup old bridges and taps
cleanup

# Generate ssh keys if needed
keygen

# Ask the server to allocate a tap for us to connect to
printf "Asking the server to allocate a tap for us..."
${ALLOCATE_TAP}
echo "[DONE]"

# Create the tap and bridge
printf "Creating the tap and bridge..."
${TAP_CREATE_COMMAND}
${TAP_UP_COMMAND}
${BRIDGE_CREATE_COMMAND}
${BRIDGE_UP_COMMAND}
# Only need on freebsd
if [ "$OS" == "FreeBSD" ]; then
	${SUDO} chown ${USER} ${TAP_PATH}
fi
echo "[DONE]"

# Join the tap and bridge
printf "Attaching tap and bridge..."
${BRIDGE_JOIN_COMMAND}
echo "[DONE]"

# Establish persistent ssh connection with system link server
printf "Connecting to systemlink network..."
CONNECT_CMD=`${FETCH_CONNECT}`
$CONNECT_CMD
echo "[DONE]"

# Wait for the tunnel to be established
sleep 10

# Run dhcp on the bridge
${SUDO} dhclient ${BRIDGE}

# Ping our gateway, show a dialog of our status
ping -q -c 1 ${REMOTE_BRIDGE} > /dev/null 2>&1
if [ "$?" != "0" ]; then
	dialog --backtitle "${BACK_TITLE}" --msgbox "Unable to connect." 10 30 && exit 1 
else
	dialog --backtitle "${BACK_TITLE}" --msgbox "Connected to the System Link Network!" 10 30 && exit 0
fi
