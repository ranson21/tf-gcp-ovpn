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

# Function to check command success
check_cmd() {
    if [ $? -ne 0 ]; then
        log "Error: $1 failed"
        return 1
    else
        log "Success: $1 completed"
        return 0
    fi
}

# Function to wait for service
wait_for_service() {
    local service=$1
    local max_attempts=30
    local attempt=1
    
    log "Waiting for $service to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet $service; then
            log "$service is ready"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: $service not ready yet, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log "Failed to start $service after $max_attempts attempts"
    return 1
}

# Function to wait for package manager
wait_for_apt() {
    local max_wait=900  # 15 minutes
    local start_time=$(date +%s)
    log "Waiting for package manager to complete..."
    
    while true; do
        if ! pgrep -f "apt|dpkg" > /dev/null; then
            log "No package manager processes running"
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait ]; then
            log "Timeout waiting for package manager after $max_wait seconds"
            return 1
        fi
        
        if [ $((elapsed % 60)) -eq 0 ]; then
            log "Still waiting for package manager... ($elapsed seconds elapsed)"
            ps aux | grep -E "apt|dpkg" | grep -v grep || true
        fi
        
        sleep 5
    done
    
    return 0
}

# Function to verify package installation
verify_packages() {
    local packages="$1"
    local all_installed=true
    
    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log "Package $pkg is not installed"
            all_installed=false
        else
            log "Package $pkg is installed correctly"
        fi
    done
    
    $all_installed
}

# Function to generate client certificates
generate_client_certificates() {
    log "Generating client certificates"
    cd /etc/openvpn/easy-rsa || return 1
    
    # Generate client certificate and key
    printf "yes\n" | ./easyrsa build-client-full client nopass
    check_cmd "Client certificate generation" || return 1
    
    # Copy client certificates to OpenVPN directory
    cp pki/ca.crt /etc/openvpn/
    cp pki/issued/client.crt /etc/openvpn/
    cp pki/private/client.key /etc/openvpn/
    
    # Generate TLS auth key
    openvpn --genkey --secret /etc/openvpn/ta.key
    
    # Set proper permissions
    chown www-data:www-data /etc/openvpn/client.crt
    chown www-data:www-data /etc/openvpn/client.key
    chown www-data:www-data /etc/openvpn/ca.crt
    chown www-data:www-data /etc/openvpn/ta.key
    
    chmod 644 /etc/openvpn/client.crt
    chmod 644 /etc/openvpn/ca.crt
    chmod 600 /etc/openvpn/client.key
    chmod 600 /etc/openvpn/ta.key
    
    return 0
}

# Function to setup auth service
setup_auth_service() {
    log "Setting up auth service"
    
    # Get external IP with retries
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
            http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
        if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" != "0.0.0.0" ]]; then
            break
        fi
        log "Attempt $attempt: Waiting for external IP..."
        sleep 10
        attempt=$((attempt + 1))
    done

    if [[ -z "$EXTERNAL_IP" || "$EXTERNAL_IP" == "0.0.0.0" ]]; then
        log "Failed to get external IP"
        return 1
    fi
    
    # Create directory for the auth service
    mkdir -p /opt/vpn-auth
    
    # Copy the Python script
    cat > /opt/vpn-auth/vpn_auth.py <<'EOF'
${vpn_auth_py}
EOF
    
    chmod +x /opt/vpn-auth/vpn_auth.py
    
    # Set up environment file
    cat > /opt/vpn-auth/auth.env <<EOF
CLIENT_ID="${client_id}"
ALLOWED_DOMAIN="${domain}"
EXTERNAL_IP="$EXTERNAL_IP"
EOF
    
    # Create systemd service
    cat > /etc/systemd/system/vpn-auth.service <<EOF
[Unit]
Description=OpenVPN Google Authentication Service
After=network.target
Requires=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/vpn-auth
EnvironmentFile=/opt/vpn-auth/auth.env
ExecStart=/usr/bin/python3 /opt/vpn-auth/vpn_auth.py
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chown -R www-data:www-data /opt/vpn-auth
    chmod 600 /opt/vpn-auth/auth.env
    
    systemctl daemon-reload
    systemctl enable vpn-auth
    systemctl start vpn-auth
    
    wait_for_service vpn-auth
    return $?
}

# Function to setup nginx
setup_nginx() {
    log "Setting up nginx"
    
    # Create self-signed certificates
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx-selfsigned.key \
        -out /etc/nginx/ssl/nginx-selfsigned.crt \
        -subj "/CN=$EXTERNAL_IP"
    
    # Configure nginx
    cat > /etc/nginx/sites-available/vpn-portal <<EOF
server {
    listen 443 ssl;
    server_name $EXTERNAL_IP;

    ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://localhost:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name $EXTERNAL_IP;
    return 301 https://\$host\$request_uri;
}
EOF

    # Enable site and disable default
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/vpn-portal /etc/nginx/sites-enabled/

    # Set permissions
    chown -R www-data:www-data /etc/nginx/ssl
    chmod 600 /etc/nginx/ssl/nginx-selfsigned.key
    chmod 644 /etc/nginx/ssl/nginx-selfsigned.crt

    # Test and restart nginx
    nginx -t && systemctl restart nginx
    
    wait_for_service nginx
    return $?
}

# Main installation process
log "Starting installation process"

# Update package list
log "Updating package list"
apt-get update

# Configure apt to be non-interactive
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Install packages
log "Installing packages"
apt-get install -y \
    openvpn \
    easy-rsa \
    nginx \
    python3-pip \
    python3-flask \
    certbot \
    python3-certbot-nginx \
    wget \
    curl \
    iptables-persistent

wait_for_apt
check_cmd "Package installation" || exit 1

# Install Python packages
log "Installing Python packages"
pip3 install --no-cache-dir \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    requests

# Set up Easy-RSA and PKI
log "Setting up Easy-RSA"
if [ ! -d "/etc/openvpn/easy-rsa" ]; then
    make-cadir /etc/openvpn/easy-rsa
    check_cmd "make-cadir" || exit 1
fi

cd /etc/openvpn/easy-rsa || exit 1

# Initialize PKI
log "Initializing PKI"
./easyrsa init-pki
check_cmd "PKI initialization" || exit 1

log "Building CA"
printf "yes\n" | ./easyrsa build-ca nopass
check_cmd "CA building" || exit 1

log "Building server certificate"
printf "yes\n" | ./easyrsa build-server-full server nopass
check_cmd "Server certificate building" || exit 1

log "Generating DH parameters"
printf "yes\n" | ./easyrsa gen-dh
check_cmd "DH parameters generation" || exit 1

# Copy keys and certificates
log "Copying certificates"
for file in "pki/ca.crt" "pki/issued/server.crt" "pki/private/server.key" "pki/dh.pem"; do
    if [ -f "$file" ]; then
        cp "$file" /etc/openvpn/
        check_cmd "Copying $file" || log "Warning: Failed to copy $file"
    else
        log "Error: $file does not exist"
        exit 1
    fi
done

# Generate client certificates
generate_client_certificates
check_cmd "Client certificate generation" || exit 1

# Set up authentication service
setup_auth_service
check_cmd "Auth service setup" || exit 1

# Set up nginx
setup_nginx
check_cmd "Nginx setup" || exit 1

# Create OpenVPN server config
log "Creating OpenVPN config"
cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

# Enable IP forwarding
log "Configuring IP forwarding"
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip-forward.conf
sysctl -p /etc/sysctl.d/99-ip-forward.conf

# Configure iptables
log "Configuring iptables"
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
netfilter-persistent save

# Start OpenVPN
systemctl enable openvpn@server
systemctl start openvpn@server
wait_for_service openvpn@server

log "Setup complete!"