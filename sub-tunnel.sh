#!/bin/bash
clear
read -p "Destination IP: " DEST_IP
read -p "SSH Password " SSH_PASS
read -p "Source Port: " SRC_PORT
read -p "Destination Port: " DEST_PORT
read -p "SSH Port: " SSH_PORT

# Validate input
if [[ -z "$DEST_IP" || -z "$SSH_PASS" ]]; then
  echo "Usage: $0 <destination_ip> <ssh_password> [source_port] [destination_port] [ssh_port]"
  exit 1
fi

SERVICE_NAME="ssh-tunnel${SRC_PORT}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Check if a tunnel on this port already exists
if systemctl list-units --full -all | grep -q "$SERVICE_NAME"; then
  echo "⚠️  A tunnel using port $SRC_PORT already exists as $SERVICE_NAME."
  read -p "Do you want to stop and remove the existing tunnel? [y/N]: " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "[+] Stopping and disabling $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    echo "[+] Removed existing tunnel on port $SRC_PORT."
  else
    echo "❌ Aborting to avoid conflict on port $SRC_PORT."
    exit 1
  fi
fi

# Generate SSH key
echo "[+] Generating SSH key..."
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "s1-to-s2" <<< y >/dev/null

# Install sshpass if not present
if ! command -v sshpass &>/dev/null; then
  echo "[+] Installing sshpass..."
  apt-get update && apt-get install -y sshpass
fi

# Copy SSH key to server 2
echo "[+] Copying SSH key to $DEST_IP..."
sshpass -p "$SSH_PASS" ssh-copy-id -i /root/.ssh/id_rsa.pub -p "$SSH_PORT" -o StrictHostKeyChecking=no root@"$DEST_IP"

# Create systemd service
echo "[+] Creating systemd service at $SERVICE_FILE..."

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Persistent SSH Tunnel: Forward port $SRC_PORT to $DEST_IP:$DEST_PORT
After=network.target

[Service]
ExecStart=/usr/bin/ssh -p $SSH_PORT -i /root/.ssh/id_rsa -N -L 0.0.0.0:$SRC_PORT:$DEST_IP:$DEST_PORT root@$DEST_IP
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
echo "[+] Enabling and starting the SSH tunnel service..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# Show status
echo "[+] Tunnel setup complete. Service status:"
systemctl status "$SERVICE_NAME"
