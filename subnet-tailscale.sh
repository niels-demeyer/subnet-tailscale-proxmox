#!/bin/bash
# filepath: setup-tailscale-subnet-router.sh

set -e

# Default configuration
CONTAINER_ID=100
SUBNET=""
AUTO_DETECT_IP=true

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup Tailscale subnet routing in a Proxmox LXC container.

OPTIONS:
    -c, --container ID      LXC container ID to configure (default: 100)
    -s, --subnet CIDR       Subnet or IP to advertise (default: auto-detect container IP)
                            - Use CIDR notation for subnets: 192.168.1.0/24
                            - Use single IP for specific host: 192.168.1.10 (auto-converts to /32)
                            - If not specified, will auto-detect the container's IP address
    -i, --ipaddr CIDR       Alias for --subnet
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Use defaults (container 100, auto-detect IP)
    $0 --container 102                          # Use container 102 with auto-detected IP
    $0 --subnet 192.168.1.0/24                 # Advertise entire /24 subnet (overrides auto-detect)
    $0 --subnet 192.168.129.59                 # Advertise single IP (auto-converts to /32)
    $0 --container 102 --subnet 192.168.1.10   # Custom container with single IP
    $0 -c 102 -s 192.168.1.0/24               # Short form flags

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--container)
            CONTAINER_ID="$2"
            shift 2
            ;;
        -s|--subnet|-i|--ipaddr)
            SUBNET="$2"
            AUTO_DETECT_IP=false
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate container ID is numeric
if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Container ID must be numeric"
    exit 1
fi

# Check if container exists early
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

# Function to get container IP address
get_container_ip() {
    local container_id=$1
    # Try to get the primary IP address from the container
    # This filters out localhost and gets the first valid IPv4 address
    local ip=$(pct exec $container_id -- ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    echo "$ip"
}

# Auto-detect container IP if subnet not specified
if [ "$AUTO_DETECT_IP" = true ] && [ -z "$SUBNET" ]; then
    echo "Auto-detecting container IP address..."
    DETECTED_IP=$(get_container_ip $CONTAINER_ID)
    
    if [ -n "$DETECTED_IP" ]; then
        SUBNET="$DETECTED_IP/32"
        echo "Detected container IP: $DETECTED_IP"
        echo "Will advertise: $SUBNET"
    else
        echo "Warning: Could not auto-detect container IP address"
        echo "Please specify a subnet manually using --subnet option"
        exit 1
    fi
elif [ -z "$SUBNET" ]; then
    echo "Error: No subnet specified and auto-detection disabled"
    exit 1
fi

# Auto-convert single IP to /32 CIDR notation if needed
if [[ $SUBNET =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && [[ ! $SUBNET =~ / ]]; then
    echo "Note: Converting single IP address to /32 CIDR notation: $SUBNET -> $SUBNET/32"
    SUBNET="$SUBNET/32"
fi

# Function to validate subnet format
validate_subnet() {
    local subnet=$1
    # Check if subnet matches CIDR format (IP/prefix)
    if [[ $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        # Extract IP and prefix
        local ip=$(echo $subnet | cut -d'/' -f1)
        local prefix=$(echo $subnet | cut -d'/' -f2)
        
        # Validate IP octets
        IFS='.' read -ra ADDR <<< "$ip"
        for octet in "${ADDR[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        
        # Validate prefix
        if (( prefix < 0 || prefix > 32 )); then
            return 1
        fi
        
        return 0
    else
        return 1
    fi
}

# Validate subnet format
if ! validate_subnet "$SUBNET"; then
    echo "Error: Invalid subnet format '$SUBNET'"
    echo "Please use CIDR notation (e.g., 192.168.1.0/24)"
    exit 1
fi

echo "=== Tailscale Subnet Router Setup for LXC Container $CONTAINER_ID ==="
echo "Subnet: $SUBNET"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
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
echo "Stopping container $CONTAINER_ID..."
pct stop $CONTAINER_ID
sleep 5
echo "Starting container $CONTAINER_ID..."
pct start $CONTAINER_ID
sleep 10

echo "Step 6: Starting Tailscale with subnet routing..."

# Enable tailscaled service to start on boot
pct exec $CONTAINER_ID -- systemctl enable tailscaled
pct exec $CONTAINER_ID -- systemctl start tailscaled

# Wait for tailscaled to be ready
sleep 5

# Configure Tailscale for subnet routing (no authentication in script)
echo "Configuring Tailscale service and persistence..."
echo "Tailscale will be ready for manual authentication through the admin console."

# Create a startup script to ensure Tailscale parameters persist after reboots
echo "Creating persistent Tailscale configuration..."
pct exec $CONTAINER_ID -- tee /usr/local/bin/tailscale-startup.sh > /dev/null << EOF
#!/bin/bash
# Tailscale startup script with subnet routing
sleep 10  # Wait for network to be ready

# Only apply subnet routing if Tailscale is already authenticated
if tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
    # Already authenticated, apply/update subnet routes
    tailscale up --advertise-routes=$SUBNET --accept-routes --advertise-exit-node=false >/dev/null 2>&1
fi
# Note: No authentication attempts in this script - handle via admin console
EOF

# Make the startup script executable
pct exec $CONTAINER_ID -- chmod +x /usr/local/bin/tailscale-startup.sh

# Create systemd service to run the startup script on boot
pct exec $CONTAINER_ID -- tee /etc/systemd/system/tailscale-subnet.service > /dev/null << EOF
[Unit]
Description=Tailscale Subnet Router Configuration
After=network.target tailscaled.service
Wants=tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tailscale-startup.sh
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

# Enable the custom service
pct exec $CONTAINER_ID -- systemctl daemon-reload
pct exec $CONTAINER_ID -- systemctl enable tailscale-subnet.service

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Container ID: $CONTAINER_ID"
echo "Advertised subnet: $SUBNET"
echo "Configuration backup: /etc/pve/lxc/${CONTAINER_ID}.conf.backup"
echo ""
echo "Tailscale has been configured to:"
echo "✓ Start automatically on container boot"
echo "✓ Maintain subnet routing configuration after reboots"
echo "✓ Advertise subnet: $SUBNET"
echo "✓ Ready for manual authentication"
echo ""
echo "Next steps:"
echo "1. SSH into the container: pct enter $CONTAINER_ID"
echo "2. Run: tailscale up --advertise-routes=$SUBNET --accept-routes --advertise-exit-node=false"
echo "3. Follow the authentication URL that appears"
echo "4. Or go to https://login.tailscale.com/admin/machines to authenticate"
echo "5. Approve the subnet routes for $SUBNET"
echo "6. Test connectivity from another device on your Tailscale network"
echo ""
echo "After authentication, the container will automatically maintain Tailscale"
echo "subnet routing even after reboots. UDP GRO forwarding has been optimized on vmbr0."
