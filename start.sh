#!/bin/sh
USERNAME=${GNS3_USERNAME:-gns3}

if [ "${CONFIG}x" == "x" ]; then
	CONFIG=/data/configs/$USERNAME/$USERNAME-config.ini

fi

if [ ! -e $CONFIG ]; then
  mkdir -p /data/configs/$USERNAME
  mkdir -p /data/projects/$USERNAME
	cp /config.ini $CONFIG
fi

brctl addbr virbr0
ip link set dev virbr0 up
if [ "${BRIDGE_ADDRESS}x" == "x" ]; then
  BRIDGE_ADDRESS=172.21.1.1/24
fi
ip ad add ${BRIDGE_ADDRESS} dev virbr0
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

openvpn --daemon --config /data/gns3.ovpn

# Wait until the VPN route is up
until ip route get 10.0.0.1 2>/dev/null | grep -q 'dev tun0'; do
    echo "Waiting for VPN tunnel to come up..."
    sleep 1
done

# Safely get the IP using sed
TUN_IP=$(ip route get 10.0.0.1 | sed -n 's/.*src \([0-9\.]*\).*/\1/p')
echo "Tunnel IP: $TUN_IP"

# Update default username password
sed -i "s/^\(default_admin_username = \).*/\1$USERNAME/" "$CONFIG"
sed -i "s/^\(default_admin_password = \).*/\1$USERNAME/" "$CONFIG"

# Update the config file with the new IP
sed -i "s/^\(host = \).*/\1$TUN_IP/" "$CONFIG"

# Update project file directory to username
sed -i "s/^\(projects_path = \).*/\1\/data\/projects\/$USERNAME/" "$CONFIG"

dnsmasq -i virbr0 -z -h --dhcp-range=172.21.1.10,172.21.1.250,4h
dockerd --storage-driver=vfs --data-root=/data/docker/ &
gns3server -A --config $CONFIG