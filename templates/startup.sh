#!/bin/bash

# Enable logging and error handling
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/var/log/startup-script.log 2>&1

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    log "Error occurred in line $1"
    return 1
}

trap 'handle_error $LINENO' ERR

# Update package list
log "Updating package list"
apt-get update

# Configure apt to be non-interactive
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Install required packages
log "Installing packages"
apt-get install -y \
    openvpn \
    easy-rsa \
    nginx \
    python3-pip \
    git \
    make \
    curl \
    iptables-persistent

# Set up Easy-RSA and PKI
log "Setting up Easy-RSA"
if [ ! -d "/etc/openvpn/easy-rsa" ]; then
    make-cadir /etc/openvpn/easy-rsa
fi

cd /etc/openvpn/easy-rsa || exit 1

# Initialize PKI
log "Initializing PKI"
./easyrsa init-pki
printf "yes\n" | ./easyrsa build-ca nopass
printf "yes\n" | ./easyrsa build-server-full server nopass
printf "yes\n" | ./easyrsa gen-dh

# Copy keys and certificates
log "Copying certificates"
cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem /etc/openvpn/

# Generate client certificates
log "Generating client certificates"
printf "yes\n" | ./easyrsa build-client-full client nopass
cp pki/ca.crt /etc/openvpn/
cp pki/issued/client.crt /etc/openvpn/
cp pki/private/client.key /etc/openvpn/
openvpn --genkey --secret /etc/openvpn/ta.key

# Set proper permissions
chown -R www-data:www-data /etc/openvpn
chmod 600 /etc/openvpn/*.key
chmod 644 /etc/openvpn/*.crt /etc/openvpn/*.pem

# Create OpenVPN server config
log "Creating OpenVPN config"
cat > /etc/openvpn/server.conf <<'EOF'
${openvpn_conf}
EOF

# Setup nginx SSL
log "Setting up nginx SSL"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx-selfsigned.key \
    -out /etc/nginx/ssl/nginx-selfsigned.crt \
    -subj "/CN=${external_ip}"

# Configure nginx
log "Configuring nginx"
cat > /etc/nginx/sites-available/vpn-portal <<'EOF'
${nginx_conf}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/vpn-portal /etc/nginx/sites-enabled/

# Clone and setup VPN web interface
log "Setting up VPN web interface"
cd /opt || exit 1
git clone https://github.com/ranson21/ovpn-client-web.git
cd ovpn-client-web || exit 1

# Create environment file
cat > .env <<EOF
CLIENT_ID="${client_id}"
ALLOWED_DOMAIN="${domain}"
EXTERNAL_IP="${external_ip}"
EOF

# Install dependencies and run
make install
make build

# Create systemd service for VPN web interface
cat > /etc/systemd/system/vpn-web.service <<'EOF'
${systemd_unit}
EOF

# Set proper permissions
chown -R www-data:www-data /opt/ovpn-client-web
chmod 600 /opt/ovpn-client-web/.env

# Enable and start services
systemctl daemon-reload
systemctl enable vpn-web
systemctl enable openvpn@server
systemctl enable nginx

systemctl start vpn-web
systemctl start openvpn@server
systemctl start nginx

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip-forward.conf
sysctl -p /etc/sysctl.d/99-ip-forward.conf

# Configure iptables
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ens4 -j MASQUERADE
iptables -A FORWARD -i tun0 -o ens4 -j ACCEPT
iptables -A FORWARD -i ens4 -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT

netfilter-persistent save

log "Setup complete!"