#!/bin/sh

log() {
    echo "[*] $1"
}

log "Setting up OpenVPN"

#MY_IP_ADDR=$(dig @ns1.google.com -t txt o-o.myaddr.l.google.com +short -4 | sed 's/"//g')

MY_IP_ADDR=${OPENVPN_SRVR_IP:-$(dig @ns1.google.com -t txt o-o.myaddr.l.google.com +short -4 | sed 's/"//g')}

log "IP detected: $MY_IP_ADDR"

UUID=${UUID:-$(uuidgen)}
log "UUID to use for the OpenVPN client config: $UUID"

mkdir -p /etc/openvpn/
mkdir -p /data/ovpns  # persistent config directory

[ -d /dev/net ] || mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

log "Creating OpenVPN keys"

[ -f /etc/openvpn/dh.pem ] || openssl dhparam -out /etc/openvpn/dh.pem 2048
[ -f /etc/openvpn/key.pem ] || openssl genrsa -out /etc/openvpn/key.pem 2048
chmod 600 /etc/openvpn/key.pem
[ -f /etc/openvpn/csr.pem ] || openssl req -new -key /etc/openvpn/key.pem -out /etc/openvpn/csr.pem -subj /CN=OpenVPN/
[ -f /etc/openvpn/cert.pem ] || openssl x509 -req -in /etc/openvpn/csr.pem -out /etc/openvpn/cert.pem -signkey /etc/openvpn/key.pem -days 24855

log "Creating OpenVPN client configuration"
cat <<EOFCLIENT > /root/client.ovpn
client
nobind
comp-lzo
dev tun
proto udp
<key>
$(cat /etc/openvpn/key.pem)
</key>
<cert>
$(cat /etc/openvpn/cert.pem)
</cert>
<ca>
$(cat /etc/openvpn/cert.pem)
</ca>
<connection>
remote $MY_IP_ADDR 1194 udp
</connection>
EOFCLIENT

cp /root/client.ovpn /data/ovpns/$UUID.ovpn  # save to persistent storage

cat <<EOFCONF > /etc/openvpn/openvpn.conf
server 10.0.0.0 255.255.255.0
verb 3
duplicate-cn
comp-lzo
key /etc/openvpn/key.pem
ca /etc/openvpn/cert.pem
cert /etc/openvpn/cert.pem
dh /etc/openvpn/dh.pem
keepalive 10 60
ifconfig-pool-persist ipp.txt
push "route 10.0.0.0 255.0.0.0"
push "dhcp-option DNS 10.0.0.1"
persist-key
persist-tun
proto udp
port 1194
user nobody
group nobody
dev tun1194
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
EOFCONF

# (Optional) Let OpenRC shut up if needed
mkdir -p /run/openrc
touch /run/openrc/softlevel

log "Restarting OpenVPN and GNS3"

log "Starting OpenVPN manually"
openvpn --config /etc/openvpn/openvpn.conf &

log "VPN client config saved to /data/ovpns/$UUID.ovpn"

exec /start.sh
