#!/bin/bash
# filepath: setup-tailscale-subnet-router.sh

set -e

# Configuration
CONTAINER_ID=${1:-100}
SUBNET="192.168.128.0/23"

echo "=== Tailscale Subnet Router Setup for LXC Container $CONTAINER_ID ==="
echo "Subnet: $SUBNET"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Check if container exists
if ! pct status $CONTAINER_ID &> /dev/null; then
    echo "Error: Container $CONTAINER_ID does not exist"
    exit 1
fi

# Check if container is running
if [ "$(pct status $CONTAINER_ID | grep -oP '(?<=status: )\w+')" != "running" ]; then
    echo "Starting container $CONTAINER_ID..."
    pct start $CONTAINER_ID
    sleep 5
fi

echo "Step 1: Installing Tailscale in container..."
pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://tailscale.com/install.sh | sh"

echo "Step 2: Enabling IP forwarding..."
pct exec $CONTAINER_ID -- bash -c "echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf"
pct exec $CONTAINER_ID -- bash -c "echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf"
pct exec $CONTAINER_ID -- sysctl -p

echo "Step 3: Configuring LXC container permissions..."
# Backup original config
cp /etc/pve/lxc/${CONTAINER_ID}.conf /etc/pve/lxc/${CONTAINER_ID}.conf.backup

# Add required permissions if not already present
if ! grep -q "lxc.cgroup2.devices.allow: c 10:200 rwm" /etc/pve/lxc/${CONTAINER_ID}.conf; then
    echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /etc/pve/lxc/${CONTAINER_ID}.conf
fi

if ! grep -q "lxc.mount.entry: /dev/net/tun" /etc/pve/lxc/${CONTAINER_ID}.conf; then
    echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /etc/pve/lxc/${CONTAINER_ID}.conf
fi

echo "Step 4: Optimizing UDP GRO on host (vmbr0)..."
# Enable UDP GRO forwarding on the bridge interface
ethtool -K vmbr0 rx-udp-gro-forwarding on &>/dev/null || echo "Note: UDP GRO optimization not available on this kernel"

# Make it persistent across reboots
ETHTOOL_CONF="/etc/network/if-up.d/ethtool-gro"
if [ ! -f "$ETHTOOL_CONF" ]; then
    cat > "$ETHTOOL_CONF" << 'EOF'
#!/bin/bash
if [ "$IFACE" = "vmbr0" ]; then
    ethtool -K vmbr0 rx-udp-gro-forwarding on 2>/dev/null || true
fi
EOF
    chmod +x "$ETHTOOL_CONF"
    echo "Created persistent UDP GRO configuration"
fi

echo "Step 5: Restarting container to apply changes..."
pct restart $CONTAINER_ID
sleep 10

echo "Step 6: Starting Tailscale with subnet routing..."
pct exec $CONTAINER_ID -- tailscale up --advertise-routes=$SUBNET --accept-routes --advertise-exit-node=false

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Next steps:"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find your container and approve the subnet routes"
echo "3. Test connectivity from another device on your Tailscale network"
echo ""
echo "Container ID: $CONTAINER_ID"
echo "Advertised subnet: $SUBNET"
echo "Configuration backup: /etc/pve/lxc/${CONTAINER_ID}.conf.backup"
echo ""
echo "UDP GRO forwarding has been optimized on vmbr0"
