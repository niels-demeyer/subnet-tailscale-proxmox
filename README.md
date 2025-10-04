# Tailscale Subnet Router for Proxmox LXC

This script automates the setup of Tailscale subnet routing in a Proxmox LXC container, allowing you to expose your local network subnets through Tailscale.

## Overview

The script configures an LXC container to act as a Tailscale subnet router, which allows devices on your Tailscale network to access resources on your local network (e.g., `192.168.128.0/23`) through the container.

## Features

- ✅ Automatic Tailscale installation in LXC container
- ✅ IP forwarding configuration
- ✅ LXC container permission setup for TUN/TAP devices
- ✅ UDP GRO optimization for better performance
- ✅ Automatic container restart and service startup
- ✅ Configuration backup creation
- ✅ Container existence and status validation
- ✅ Persistent subnet routing across container reboots
- ✅ Automatic Tailscale service startup on boot

## Requirements

- Proxmox VE host
- Root access on the Proxmox host (script must be run as root)
- LXC container (will be created if specified ID doesn't exist)
- Internet connectivity for Tailscale installation

**Note:** Proxmox VE hosts typically don't have `sudo` installed by default. The script is designed to run as root, which is the standard way to manage Proxmox systems.

## Usage

### Direct Execution

```bash
# Run with default settings (container ID: 100, subnet: 192.168.128.0/23)
sudo ./subnet-tailscale.sh

# Show help and available options
sudo ./subnet-tailscale.sh --help

# Run with specific container ID
sudo ./subnet-tailscale.sh --container 102

# Run with custom subnet (using --subnet flag)
sudo ./subnet-tailscale.sh --subnet 192.168.1.0/24

# Run with custom subnet (using --ipaddr alias)
sudo ./subnet-tailscale.sh --ipaddr 192.168.1.0/24

# Run with both custom container and subnet
sudo ./subnet-tailscale.sh --container 102 --subnet 192.168.1.0/24

# Short form flags
sudo ./subnet-tailscale.sh -c 102 -s 192.168.1.0/24

# Mixed usage
sudo ./subnet-tailscale.sh -c 102 --ipaddr 10.0.0.0/16
```

### Remote Execution with curl

Execute the script directly from GitHub:

**For Proxmox VE hosts (no sudo required, run as root):**

```bash
# Default settings (container: 100, subnet: 192.168.128.0/23)
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash

# Show help
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- --help

# Specific container ID
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- --container 102

# Custom subnet
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- --subnet 192.168.1.0/24

# Custom container and subnet
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- --container 102 --subnet 192.168.1.0/24

# Using short flags
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- -c 102 -s 192.168.1.0/24

# Using --ipaddr alias
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash -s -- --ipaddr 10.0.0.0/16
```

**For other Linux systems (with sudo):**

```bash
# Default settings (container: 100, subnet: 192.168.128.0/23)
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | sudo bash

# Custom container and subnet
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | sudo bash -s -- --container 102 --subnet 192.168.1.0/24
```

### One-liner Installation

**For Proxmox VE hosts (run as root):**

```bash
# Quick setup with default settings
bash -c "$(curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh)"
```

**For other Linux systems (with sudo):**

```bash
# Quick setup with default settings
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh)"
```

## Configuration

### Script Parameters

| Flag             | Short | Description                   | Default            | Example                   |
| ---------------- | ----- | ----------------------------- | ------------------ | ------------------------- |
| `--container ID` | `-c`  | LXC container ID to configure | `100`              | `--container 102`         |
| `--subnet CIDR`  | `-s`  | Subnet to advertise (CIDR)    | `192.168.128.0/23` | `--subnet 192.168.1.0/24` |
| `--ipaddr CIDR`  | `-i`  | Alias for --subnet            | `192.168.128.0/23` | `--ipaddr 192.168.1.0/24` |
| `--help`         | `-h`  | Show help message             | N/A                | `--help`                  |

### Configurable Variables

The script now uses command-line flags for configuration:

```bash
# Default values (used when flags are not provided)
CONTAINER_ID=100                 # Default container ID
SUBNET="192.168.128.0/23"       # Default subnet to advertise
```

### Available Flags

- `--container` / `-c`: Specify LXC container ID
- `--subnet` / `-s`: Specify subnet in CIDR notation
- `--ipaddr` / `-i`: Alias for --subnet (for convenience)
- `--help` / `-h`: Display usage information

### Subnet Validation

The script includes automatic validation for subnet format:

- Must be in CIDR notation (e.g., `192.168.1.0/24`)
- IP octets must be between 0-255
- Prefix must be between 0-32
- Container ID must be numeric

### Custom Configuration Examples

```bash
# Example: Use container 102 with subnet 192.168.1.0/24
sudo ./subnet-tailscale.sh --container 102 --subnet 192.168.1.0/24

# Example: Use short flags
sudo ./subnet-tailscale.sh -c 101 -s 10.0.0.0/8

# Example: Use --ipaddr alias
sudo ./subnet-tailscale.sh --container 102 --ipaddr 192.168.100.0/28

# Example: Only change container (use default subnet)
sudo ./subnet-tailscale.sh --container 105

# Example: Only change subnet (use default container)
sudo ./subnet-tailscale.sh --subnet 172.16.0.0/16
```

## What the Script Does

1. **Validation**: Checks for root privileges and container existence
2. **Container Management**: Starts the container if it's not running
3. **Tailscale Installation**: Downloads and installs Tailscale in the container
4. **Network Configuration**: Enables IP forwarding for IPv4 and IPv6
5. **LXC Permissions**: Configures container permissions for TUN/TAP devices
6. **Performance Optimization**: Enables UDP GRO forwarding on the bridge interface
7. **Service Startup**: Restarts container and starts Tailscale with subnet routing
8. **Persistence Configuration**: Creates systemd service for automatic startup
9. **Backup**: Creates a backup of the original container configuration

## Persistence and Auto-Start

The script ensures that Tailscale subnet routing will work automatically even after container reboots:

- **Tailscale Service**: Enabled to start automatically on boot
- **Custom Startup Script**: `/usr/local/bin/tailscale-startup.sh` maintains subnet configuration
- **Systemd Service**: `tailscale-subnet.service` ensures subnet routing is applied on startup
- **Configuration Persistence**: Subnet parameters are preserved across reboots

This means once you run the script and approve the device in the Tailscale admin console, the subnet routing will work permanently without any manual intervention.

## Post-Setup Steps

After the script completes successfully:

1. **Approve Routes**: Go to [Tailscale Admin Console](https://login.tailscale.com/admin/machines)
2. **Find Your Container**: Locate the container in the machines list
3. **Enable Subnet Routes**: Approve the advertised subnet routes
4. **Test Connectivity**: Try accessing local network resources from other Tailscale devices

## Files Modified/Created

**Host System:**
- `/etc/pve/lxc/{CONTAINER_ID}.conf` - LXC container configuration
- `/etc/pve/lxc/{CONTAINER_ID}.conf.backup` - Backup of original configuration
- `/etc/network/if-up.d/ethtool-gro` - Persistent UDP GRO configuration

**Inside Container:**
- `/etc/sysctl.conf` - IP forwarding configuration
- `/usr/local/bin/tailscale-startup.sh` - Startup script for subnet routing
- `/etc/systemd/system/tailscale-subnet.service` - Systemd service for persistence
- Tailscale configuration files in `/var/lib/tailscale/`

## Troubleshooting

### Common Issues

**Container doesn't exist:**

```bash
Error: Container 100 does not exist
```

Solution: Create the container first or use a different container ID.

**Permission denied:**

```bash
Please run as root
```

Solution: Run the script with `sudo` or as root user.

**Sudo command not found (Proxmox VE):**

```bash
-bash: sudo: command not found
curl: (23) Failure writing output to destination
```

Solution: On Proxmox VE hosts, run without `sudo` as you're already logged in as root:

```bash
# Use this instead
curl -fsSL https://raw.githubusercontent.com/niels-demeyer/subnet-tailscale-proxmox/main/subnet-tailscale.sh | bash
```

**Invalid subnet format:**

```bash
Error: Invalid subnet format '192.168.1'
Please use CIDR notation (e.g., 192.168.1.0/24)
```

Solution: Ensure the subnet is in proper CIDR format with both IP address and prefix length.

**PCT restart command not found:**

```bash
ERROR: unknown command 'pct restart'
```

Solution: This has been fixed in the latest version of the script. The script now uses `pct stop` followed by `pct start` instead of `pct restart` for better compatibility across Proxmox versions.

**Invalid container ID:**

```bash
Error: Container ID must be numeric
```

Solution: Ensure the container ID contains only numbers.

**Unknown option:**

```bash
Error: Unknown option --invalid-flag
Use --help for usage information
```

Solution: Use `--help` to see available options, or check for typos in flag names.

**Tailscale authentication:**
After running the script, you'll need to authenticate the device through the Tailscale admin panel.

### Verification Commands

Check if Tailscale is running in the container:

```bash
pct exec 100 -- tailscale status
```

Verify IP forwarding is enabled:

```bash
pct exec 100 -- sysctl net.ipv4.ip_forward
pct exec 100 -- sysctl net.ipv6.conf.all.forwarding
```

Check container configuration:

```bash
cat /etc/pve/lxc/100.conf
```

## Security Considerations

- The container will have access to TUN/TAP devices
- IP forwarding is enabled, which allows routing between networks
- The container can act as a gateway for your local network
- Ensure proper Tailscale ACL rules are configured to limit access
