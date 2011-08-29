#! /bin/bash
# Delete tmp-data after quick exit
trap "rm tmp; rm tmp.new; rm tmp.old" SIGKILL
# Make sure, that only root proceeds
if [ $EUID -ne 0  ] ; #root:0, user:1000
then
	echo "This script must be run as root" 1>&2
	exit 1
fi

echo "Wlan-Manager by "
echo " _          _ "
echo "| | ___ __ (_)"
echo "| |/ / '_ \| |"
echo "|   <| |_) | |"
echo "|_|\_\ .__// |"
echo "     |_| |__/ "

echo "Attention, all changes are permanent."
echo "-------------------------------------"

function showNetworks {
	counter=1
	echo "[0] - ${names[0]}"
	allNetworks=`iwlist $iface scan | grep -E "ESSID"`
	for line in $allNetworks
	do
		essid=`echo $line | cut -d ":" -f 2 | sed 's/\"//g'`
		names[counter]="$essid"
		echo -n "[$counter] - "
		echo ${names[$counter]}
		counter=$(($counter+1))
	done
}

function getType {
networkType=`iwlist eth1 scan | grep -A 4 W-Robbi | grep -E "IE:" | cut -d '/' -f 2`
}

function addToConf {
	name=$1
	passwd=$2
	netType=$3

	#echo "name ($name - $1) -- passwd ($passwd - $2) -- netType ($netType - $3)"

	if [ -e tmp ] ; 
	then
		echo "File already existing"
		echo "But we still go on"
	else
		touch tmp
	fi
	echo "Generating PSK-key... ($name - $passwd)"
	wpa_passphrase "$name" "$passwd" > tmp

	# Delete last line to insert network-specific details
	sed '$d' tmp > tmp.new
	echo >> tmp.new
	
	if [[ "$netType" == *"WPA2"* ]] ; 
	then	
		echo "Adding WPA2-Info"
		echo "	# WPA2 specific details" >> tmp.new
		echo "	proto=RSN" >> tmp.new
		echo "	key_mgmt=WPA-PSK" >> tmp.new
		echo "	pairwise=CCMP TKIP" >> tmp.new
		echo "	group=CCMP TKIP" >> tmp.new
	elif [[ "$netType" == *"WPA"* ]] ; 
	then
		echo "No Info has to be added with WPA"
	elif [[ "$netType" == *"WEP"* ]] ; 
	then
		echo "Do not add 'WEP' networks to your config..."
		echo "I will connect you now, and then quit..."
		iwconfig $iface essid "$name" key s:$passwd 
		exit 0
	else
		echo "Wrong protocol"
		# Still clean up
		rm tmp
		rm tmp.new
		
		exit 1
	fi

	echo "}" >> tmp.new

	# Update real wpa_supplicant.conf
	cp $pathToWpaConf tmp.old
	cp tmp.new $pathToWpaConf
	cat tmp.old >> $pathToWpaConf

	# Cleaning up
	rm tmp
	rm tmp.new
	rm tmp.old
}

function connectToWireless {
	myIp=$1
	routerIp=$2

	ifconfig $iface up $myIp
	route add default gw $routerIp
}

# Set path to wpa_supplicant.conf
pathToWpaConf="/etc/wpa_supplicant.conf"
 
# Get wlan-Interface
iface=`iwconfig 2>/dev/null | grep -P "^[^ \t]" | cut -d\  -f1`

if [[ $iface == "" ]] ; 
then
	echo "I could not detect any suitable wlan-interface..."
	echo "Maybe you have not installed a proper wlan-driver"
	card=`(lspci; lsusb) | grep -iP "Network|Wireless|WLAN"`
	echo "Your wlan-card might be '$card'"
	echo "Look here (https://help.ubuntu.com/community/WifiDocs/WirelessCardsSupported) for the right driver!"
	exit 1
else
	echo "You are using $iface..."
fi

# Clean up, before starting
ifconfig $iface down

# Activate Interface
ifconfig $iface up

# Scan for wireless networks
echo "The following networks are avaiable:"
names[0]="Configuration"
#counter=1
#iwlist $iface scan | grep -E "ESSID" | while read line
showNetworks
echo

# Choose network
echo "Choose your desired network (enter number):"
read num

if [ $num -eq "0" ] ; 
then
	while true ; do
		echo "Now configuring..."
		config[0]="Set 'wpa_supplicant.conf' path"
		config[1]="Delete known network"
		config[2]="Exit"
	
		counti=1
		for val in "${config[@]}" ; do
			echo "[$counti] - $val"
			counti=$(($counti+1))
		done
	
		echo "Choose your desired action (enter number):"
		read answ
	
		case $answ in
		"1")
			echo "Current path to 'wpa_supplicant.conf':"
			echo "$pathToWpaConf"
			echo
			echo "Enter new path:"
			read newPath
			pathToWpaConf=$newPath
			echo "New path is set."
		;;
		"2")
			echo "Which network do you want to delete?"	
		;;
		"3")
			echo "Now exiting..."
			exit 0
		;;
		esac
		echo
	done
else

	# Detect action
	if [[ "`grep ${names[$num]} $pathToWpaConf`" == "" ]] ; 
	then
	
		echo "Unknown network '${names[$num]}'"
		echo "Now configuring it..."
	
		getType
		echo "Your networks type is $networkType" 
		echo
	
		if [[ $networkType == *"No encryption"* ]] ; # Oder wasauchimmer da steht...
		then
			echo "Do not add non encrypted networks to your config..."
			echo "Now you will get connected to that network..."
			echo "And I will shut up!"
			iwconfig $iface essid ${names[$num]}
			exit 0
		else
			# Enter password
			echo "Enter your password:"
			read pass
	
			# Insert into wpa_supplicant.conf
			addToConf "${names[$num]}" "$pass" "$networkType"
			echo
			echo "'${names[$num]}' has been added to you config-file..."
		fi
	else
		echo "Known network..."
	fi
	
	echo -n "Now connecting to '"
	echo -n ${names[$num]}
	echo "' ..."
	
  wpa_supplicant -B -Dwext -i $iface -c $pathToWpaConf -dd

  if dhcpcd $iface ; then
    echo "You are connected..."
    echo "Have fun :)"
  else
    echo "DHCP request failed.."
    echo -n "Enter your desired IP adddddress: "
    read ipAddr
    gatewSug=`echo $ipAddr | sed 's/\.[0-9]*$/.1/g'`
    echo -n "Enter your gateway address: "
    read -ei "$gatewSug" gw
	  connectToWireless "$ipAddr" "$gw"
  fi
fi

