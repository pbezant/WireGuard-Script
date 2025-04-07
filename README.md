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

- If you encounter permission issues, make sure you're not running the script as root
- For connection problems, check that WireGuard tools are properly installed
- The script will attempt multiple methods to connect/disconnect if the standard methods fail

## License

This script is provided as-is under the MIT License. 