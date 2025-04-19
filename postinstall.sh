#!/bin/sh

log() {
    echo "[*] $1"
}

log "Setting up OpenVPN"

log "Changing the GNS3 server configuration to listen on VPN interface"

log "Installing required packages"

apk add --no-cache \
    nginx \
    openvpn \
    util-linux \
    bind-tools \
    openssl \
    openrc \
    && mkdir -p /etc/nginx/sites-enabled \
    && mkdir -p /etc/nginx/sites-available \
    && echo "include /etc/nginx/sites-enabled/*.conf;" >> /etc/nginx/nginx.conf

MY_IP_ADDR=$(dig @ns1.google.com -t txt o-o.myaddr.l.google.com +short -4 | sed 's/"//g')

log "IP detected: $MY_IP_ADDR"

UUID=$(uuidgen)

log "Updating motd (this will be skipped if /etc/update-motd.d doesn't exist)"
if [ -d /etc/update-motd.d ]; then
    cat <<EOFMOTD > /etc/update-motd.d/70-openvpn
#!/bin/sh
echo ""
echo "_______________________________________________________________________________________________"
echo "Download the VPN configuration here:"
echo "http://$MY_IP_ADDR:8003/$UUID/$HOSTNAME.ovpn"
echo ""
echo "And add it to your openvpn client."
echo ""
echo "apk del nginx to disable the HTTP server."
echo "And remove this file with rm /etc/update-motd.d/70-openvpn"
EOFMOTD
    chmod 755 /etc/update-motd.d/70-openvpn
fi

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
<key>
$(cat /etc/openvpn/key.pem)
</key>
<cert>
$(cat /etc/openvpn/cert.pem)
</cert>
<ca>
$(cat /etc/openvpn/cert.pem)
</ca>
<dh>
$(cat /etc/openvpn/dh.pem)
</dh>
<connection>
remote $MY_IP_ADDR 1194 udp
</connection>
EOFCLIENT

cp /root/client.ovpn /data/ovpns/$HOSTNAME.ovpn  # save to persistent storage

cat <<EOFUDP > /etc/openvpn/udp1194.conf
server 172.16.253.0 255.255.255.0
verb 3
duplicate-cn
comp-lzo
key key.pem
ca cert.pem
cert cert.pem
dh dh.pem
keepalive 10 60
persist-key
persist-tun
proto udp
port 1194
dev tun1194
status openvpn-status-1194.log
log-append /var/log/openvpn-udp1194.log
EOFUDP

log "Setting up HTTP server for serving client config"
mkdir -p /usr/share/nginx/openvpn/$UUID
cp /data/ovpns/$HOSTNAME.ovpn /usr/share/nginx/openvpn/$UUID/$HOSTNAME.ovpn
touch /usr/share/nginx/openvpn/$UUID/index.html
touch /usr/share/nginx/openvpn/index.html

cat <<EOFNGINX > /etc/nginx/sites-available/openvpn
server {
    listen 8003;
    root /usr/share/nginx/openvpn;
}
EOFNGINX

[ -f /etc/nginx/sites-enabled/openvpn ] || ln -s /etc/nginx/sites-available/openvpn /etc/nginx/sites-enabled/

rc-service nginx restart

log "Restarting OpenVPN and GNS3"

rc-service openvpn restart
rc-service gns3 restart

log "VPN client config saved to /data/ovpns/$HOSTNAME.ovpn"
log "You can also download it from: http://$MY_IP_ADDR:8003/$UUID/$HOSTNAME.ovpn"
