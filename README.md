# WireGuard VPN Manager for Older macOS Systems

A bash script for managing WireGuard VPN connections on older macOS systems (macOS Catalina/10.15 and earlier).

## Overview

This script provides a simple terminal-based interface to manage WireGuard VPN connections on older Mac systems that might not be fully compatible with newer WireGuard clients. It offers an easy way to import, connect to, and monitor WireGuard VPN configurations.

See `diagram.txt` for a visual overview of the script's functionality.

## Features

- **Import WireGuard Configurations**: Easily import `.conf` files by providing the file path
- **Connection Management**: Connect to and disconnect from configurations
- **Real-time Metrics**: View connection metrics including transfer statistics and handshake information
- **Status Display**: Always visible connection status even in the main menu
- **Configuration List**: List and manage multiple VPN configurations

## Requirements

- macOS 10.15 (Catalina) or earlier
- WireGuard tools installed (`wg` and `wg-quick` commands)
- Bash shell

## Installation

### Automatic Installation

1. Download both the `wireguard.sh` and `install.sh` scripts
2. Run the installation script:
   ```
   bash install.sh
   ```
   
The installation script will:
- Make the WireGuard script executable
- Check if Homebrew is installed and offer to install it
- Install WireGuard tools if not already present
- Create the necessary configuration directory
- Offer to run the WireGuard manager immediately

### Manual Installation

1. Download the `wireguard.sh` script
2. Make it executable:
   ```
   chmod +x wireguard.sh
   ```
3. Install WireGuard tools using Homebrew:
   ```
   brew install wireguard-tools
   ```
4. Create the configuration directory:
   ```
   mkdir -p ~/.wireguard
   ```

## Usage

Run the script from Terminal:

```
./wireguard.sh
```

### Main Menu Options

1. **Import WireGuard Configuration**: Import a `.conf` file
2. **Connect to a configuration**: Select and connect to an imported configuration
3. **Disconnect from a configuration**: Disconnect from an active VPN
4. **List configurations**: Show all imported configurations
5. **Toggle metrics display**: Show/hide detailed metrics panel
6. **Quit**: Exit the script

### Configuration Storage

All imported configurations are stored in `~/.wireguard/` directory.

## Compatibility Notes

This script is specifically designed for older macOS systems (10.15/Catalina and earlier) where the official WireGuard client might have compatibility issues. It uses direct system commands and terminal UI to provide a more reliable experience on these systems.

Key compatibility features:
- Uses terminal UI instead of GUI components
- Handles macOS-specific network interfaces (utun devices)
- Works with older versions of the WireGuard command-line tools
- Provides more detailed troubleshooting information

## Troubleshooting

### Common Issues and Solutions

#### Error 1: Connection Failed
If you get "error 1" when connecting:

1. **Run the diagnostic tools** (option 6 in the main menu):
   - Test your configuration file
   - Check network connectivity
   - Verify endpoint reachability

2. **Check configuration file format**:
   ```
   [Interface]
   PrivateKey = your-private-key-here
   Address = 10.0.0.2/32
   DNS = 8.8.8.8
   
   [Peer]
   PublicKey = server-public-key-here
   AllowedIPs = 0.0.0.0/0
   Endpoint = your-server.com:51820
   ```

3. **Common fixes**:
   ```bash
   # Fix file permissions
   chmod 600 ~/.wireguard/*.conf
   
   # Test endpoint connectivity
   nc -z your-server.com 51820
   
   # Check if another VPN is running
   sudo wg show
   ```

#### Permission Denied Errors
- Run the "Fix permissions" tool from the diagnostic menu
- Ensure you're not running the script as root
- Check that configuration files have 600 permissions

#### Network Unreachable
- Verify your internet connection
- Test if the WireGuard server endpoint is reachable
- Check if your firewall is blocking the connection
- Try a different DNS server in your configuration

#### Interface Already Exists
- Disconnect any existing WireGuard connections first
- Use option 3 to disconnect, then try connecting again
- Check for other VPN software that might conflict

### Configuration Examples

#### Basic VPN Configuration
```ini
[Interface]
PrivateKey = your-private-key-here
Address = 10.0.0.2/32
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = server-public-key-here
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
```

#### Split Tunnel Configuration
```ini
[Interface]
PrivateKey = your-private-key-here
Address = 10.0.0.2/32

[Peer]
PublicKey = server-public-key-here
AllowedIPs = 10.0.0.0/24, 192.168.1.0/24
Endpoint = vpn.example.com:51820
```

### Diagnostic Tools

The script includes comprehensive diagnostic tools (option 6):

1. **Configuration Testing**: Validates syntax and tests connectivity
2. **Network Tests**: Checks internet and endpoint connectivity  
3. **DNS Testing**: Verifies DNS resolution
4. **System Info**: Shows WireGuard installation and interface status
5. **Log Viewing**: Displays connection attempt logs
6. **Permission Fixing**: Automatically fixes file permissions

### Getting Help

If you're still having issues:

1. Run the diagnostic tools and note any errors
2. Check the connection logs in `/tmp/wireguard_connection_*.log`
3. Verify your configuration file format
4. Test basic network connectivity

- If you encounter permission issues, make sure you're not running the script as root
- For connection problems, check that WireGuard tools are properly installed
- The script will attempt multiple methods to connect/disconnect if the standard methods fail

## License

This script is provided as-is under the MIT License. 