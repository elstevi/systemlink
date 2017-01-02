#!/bin/sh

# The first thing we need is a user
SSH_HOME=`readlink -f ~/.ssh`
if [ ! -f "${SSH_HOME}/systemlink-user" ]; then
	printf "Please enter your system link username and hit enter: "
	read SSH_USER
	echo "${SSH_USER}" > "${SSH_HOME}/systemlink-user"
fi

BACK_TITLE="Halo 2 System Link Network"
OS=`uname`
PRIV_KEY_FILE="${SSH_HOME}/systemlink"
PUB_KEY_FILE="${SSH_HOME}/systemlink.pub"
REMOTE_BRIDGE="172.16.17.1"
SSH_HOST="systemlink.douglas-enterprises.com"
SSH_PORT="22"
SSH_USER=`cat ${SSH_HOME}/systemlink-user`
SSH_STD_ARGS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}"
SSH_SPEC_ARGS="-q -o BatchMode=yes -i ${PRIV_KEY_FILE}"
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

# Generate systemlink keys, if they don't exist
keygen () {
	if [ ! -f ${PRIV_KEY_FILE} ]; then
	echo	printf "Generating ssh keys..."
		ssh-keygen -q -f ${PRIV_KEY_FILE} -t ed25519 -N ''
		echo "[DONE]"
	fi
}

# Test whether we can login to the system link server
test_ssh_auth() {
        ssh ${SSH_SPEC_ARGS} ${SSH_STD_ARGS} true > /dev/null 2>&1 
        if [ "${?}" != "0" ]; then                                                                                                                                                                                                
                return 1
        else
                return 0
        fi
}

# Attempt to authenticate with the ssh server. If not able to, attempt to pair with the server
authenticate () {
	while true; do
		test_ssh_auth
		if [ "${?}" == "0" ]; then
			break
		else
			# Use password based authentication to copy our key in.
			clear
			echo "Please enter your system link password and hit enter: "
			REMOTE_CMD="mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${PUB_KEY}' >> ~/.ssh/authorized_keys"
			ssh -q ${SSH_STD_ARGS} -- "${REMOTE_CMD}"
		fi
	done
}

# If we aren't root, we are going to need to sudo some commands
if [ "${USER}" != "root" ]; then
	SUDO="sudo"
	echo "Since we aren't root, we need to use sudo. You may be asked for your local user's password below."
else
	SUDO=""
fi

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

# Test SSH connection to system link server
printf "Testing connection to system link server..."

## Store the public key in this variable for authenticate()
PUB_KEY=`cat ${PUB_KEY_FILE}`

## Attempt to authenticate
authenticate
echo "[DONE]"

# Ask the server to allocate a tap for us to connect to
printf "Asking the server to allocate a tap for us..."
REMOTE_TAP=`ssh ${SSH_STD_ARGS} ${SSH_SPEC_ARGS} -- sudo new_tap` 
REMOTE_TAP=`echo ${REMOTE_TAP} | cut -d p -f2`
printf "tap${REMOTE_TAP}..."
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
autossh -M 1200 -o Tunnel=ethernet -w ${TAP_NUM}:$REMOTE_TAP ${SSH_SPEC_ARGS} ${SSH_STD_ARGS} -N &

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
