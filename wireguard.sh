#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USER_CONFIG_DIR="$HOME/.wireguard"

# Ensure config directory exists
mkdir -p "$USER_CONFIG_DIR"

# Global variables for metrics display
METRICS_ACTIVE=false
METRICS_PID=""
METRICS_HEIGHT=12
MENU_START_LINE=0

# Function to import configuration from a file
import_config() {
    echo -e "${BLUE}Import WireGuard Configuration${NC}"
    
    echo -ne "${YELLOW}Enter the path to the configuration file: ${NC}"
    read -r import_path
    
    # Clean the path by removing quotes and escape characters
    import_path=$(echo "$import_path" | sed 's/^"//;s/"$//;s/\\//g;s/^'"'"'//;s/'"'"'$//')
    import_path=$(echo "$import_path" | xargs)  # Trim leading/trailing whitespace
    
    if [ ! -f "$import_path" ]; then
        echo -e "${RED}File not found: $import_path${NC}"
        echo -e "${YELLOW}Tip: You can drag and drop the file into the terminal window instead of typing the path.${NC}"
        # Pause briefly to show message
        sleep 2
        return
    fi
    
    config_name=$(basename "$import_path")
    config_file="$USER_CONFIG_DIR/$config_name"
    
    # Check if file already exists
    if [ -f "$config_file" ]; then
        echo -ne "${RED}Configuration '$config_name' already exists. Overwrite? (y/n): ${NC}"
        read -r overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            echo -e "${YELLOW}Cancelled.${NC}"
            # Pause briefly to show message
            sleep 1
            return
        fi
    fi
    
    # Copy file
    if cp "$import_path" "$config_file"; then
        echo -e "${GREEN}Configuration imported to $config_file${NC}"
        
        # Ask if user wants to connect now
        echo -ne "${YELLOW}Do you want to connect to this configuration now? (y/n): ${NC}"
        read -r connect_now
        if [ "$connect_now" = "y" ] || [ "$connect_now" = "Y" ]; then
            connect_to_config "$config_name"
            
            # If successfully connected, start metrics
            if is_config_connected "$config_name"; then
                start_metrics_display
            fi
        fi
        
        # Pause briefly to show message
        sleep 1
        return
    else
        echo -e "${RED}Failed to import configuration.${NC}"
        # Pause briefly to show message
        sleep 2
        return
    fi
}

# Function to check if config is already connected
is_config_connected() {
    local config_name="$1"
    local config_file="$USER_CONFIG_DIR/$config_name"
    local config_base=$(basename "$config_name" .conf)
    
    # First, check if there are any active WireGuard interfaces
    local active_interfaces=()
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            active_interfaces+=("$iface")
        fi
    done
    
    # If no active interfaces, definitely not connected
    if [ ${#active_interfaces[@]} -eq 0 ]; then
        return 1
    fi
    
    # If config file doesn't exist, can't be connected
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Get the public key from the config file to match against active interfaces
    local config_public_key=$(grep "^PublicKey" "$config_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    if [ -z "$config_public_key" ]; then
        return 1
    fi
    
    # Check each active interface to see if it matches this configuration
    for iface in "${active_interfaces[@]}"; do
        local interface_peers=$(sudo wg show "$iface" peers 2>/dev/null)
        if echo "$interface_peers" | grep -q "$config_public_key"; then
            return 0  # Found matching configuration
        fi
    done
    
    return 1  # Configuration not found in any active interface
}

# Function to get active wireguard interface for a specific config
get_active_interface_for_config() {
    local config_name="$1"
    local config_file="$USER_CONFIG_DIR/$config_name"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Get the public key from the config file
    local config_public_key=$(grep "^PublicKey" "$config_file" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    if [ -z "$config_public_key" ]; then
        return 1
    fi
    
    # Check each utun interface
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            local interface_peers=$(sudo wg show "$iface" peers 2>/dev/null)
            if echo "$interface_peers" | grep -q "$config_public_key"; then
                echo "$iface"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to get active wireguard interface (any active interface)
get_active_interface() {
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            echo "$iface"
            return 0
        fi
    done
    echo ""
    return 1
}

# Function to get active configuration name
get_active_config() {
    # Get any active interface first
    local active_interface=$(get_active_interface)
    
    if [ -z "$active_interface" ]; then
        return 1
    fi
    
    # Get the public key from the active interface
    local active_public_key=$(sudo wg show "$active_interface" peers 2>/dev/null | head -1)
    
    if [ -z "$active_public_key" ]; then
        return 1
    fi
    
    # Find which configuration file matches this public key
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            local config_public_key=$(grep "^PublicKey" "$config" | head -1 | cut -d'=' -f2 | tr -d ' ')
            if [ "$config_public_key" = "$active_public_key" ]; then
                basename "$config"
                return 0
            fi
        fi
    done
    
    echo ""
    return 1
}

# Function to update the metrics display
update_metrics_display() {
    local interface=$(get_active_interface)
    
    if [ -z "$interface" ]; then
        METRICS_ACTIVE=false
        return 1
    fi
    
    local config_name=$(get_active_config)
    if [ -z "$config_name" ]; then
        config_name="Unknown"
    fi
    
    # Save original cursor position
    tput sc
    
    # Move to top of terminal
    tput cup 0 0
    
    # Line 0: Header
    printf "${BLUE}══════════════════════════════════════${NC}\n"
    
    # Line 1: Title
    printf "${BLUE}   WireGuard Connection Metrics   ${NC}\n"
    
    # Line 2: Header bottom
    printf "${BLUE}══════════════════════════════════════${NC}\n"
    
    # Line 3: Interface info
    printf "${GREEN}Interface: %s | Config: %s${NC}\n" "$interface" "$config_name"
    
    # Line 4: Last update time
    printf "${YELLOW}Last update: %s${NC}\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    
    # Line 5: Interface Details Header
    printf "${YELLOW}Interface Details:${NC}\n"
    
    # Get interface details (limited to keep display compact)
    local interface_details
    interface_details=$(sudo wg show "$interface" | grep -v "transfer\|handshake" | head -3)
    
    # Lines 6-8: Interface Details
    while IFS= read -r line; do
        printf "  %s\n" "$line"
    done <<< "$interface_details"
    
    # Fill any remaining lines if interface details had fewer than 3 lines
    local lines_count
    lines_count=$(echo "$interface_details" | wc -l | tr -d ' ')
    for ((i=lines_count; i<3; i++)); do
        printf "\n"
    done
    
    # Line 9: Traffic header
    printf "${YELLOW}Traffic Statistics:${NC}\n"
    
    # Lines 10-11: Traffic stats
    local handshake_line
    handshake_line=$(sudo wg show "$interface" | grep "handshake")
    local transfer_line
    transfer_line=$(sudo wg show "$interface" | grep "transfer")
    
    if [ -n "$handshake_line" ]; then
        printf "  ${GREEN}%s${NC}\n" "$handshake_line"
    else
        printf "  ${RED}No handshake information${NC}\n"
    fi
    
    if [ -n "$transfer_line" ]; then
        printf "  ${GREEN}%s${NC}\n" "$transfer_line"
    else
        printf "  ${RED}No transfer information${NC}\n"
    fi
    
    # Restore cursor position
    tput rc
}

# Function to stop metrics display
stop_metrics_display() {
    if [ -n "$METRICS_PID" ]; then
        kill "$METRICS_PID" 2>/dev/null
        METRICS_PID=""
    fi
    METRICS_ACTIVE=false
    
    # Clear screen
    clear
}

# Function to start metrics display in background
start_metrics_display() {
    # Stop any existing metrics display
    if [ -n "$METRICS_PID" ]; then
        kill "$METRICS_PID" 2>/dev/null
    fi
    
    # Clear screen
    clear
    
    METRICS_ACTIVE=true
    
    # First display of metrics
    update_metrics_display
    
    # Set cursor position for menu
    MENU_START_LINE=12
    tput cup "$MENU_START_LINE" 0
    
    # Launch background process for updates
    (
        while $METRICS_ACTIVE; do
            sleep 2
            if $METRICS_ACTIVE; then
                update_metrics_display
                
                # Force cursor back to menu position
                tput cup "$MENU_START_LINE" 0
            fi
        done
    ) &
    
    # Store the process ID
    METRICS_PID=$!
}

# Function to connect to a configuration
connect_to_config() {
    local config_name="$1"
    local config_file="$USER_CONFIG_DIR/$config_name"
    local config_base=$(basename "$config_name" .conf)
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Configuration file not found: $config_file${NC}"
        return 1
    fi
    
    # Check if already connected
    if is_config_connected "$config_name"; then
        echo -e "${YELLOW}Connection to WireGuard is already active.${NC}"
        echo -ne "${YELLOW}Do you want to disconnect and reconnect? (y/n): ${NC}"
        read -r reconnect
        if [ "$reconnect" = "y" ] || [ "$reconnect" = "Y" ]; then
            disconnect_from_config "$config_name" && sleep 2
        else
            # Already connected, return success
            return 0
        fi
    fi
    
    echo -e "${BLUE}Connecting to $config_name...${NC}"
    
    # Check if WireGuard is installed
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}WireGuard is not installed. Please install it first.${NC}"
        return 1
    fi
    
    # Validate configuration before attempting connection
    echo -e "${YELLOW}Validating configuration...${NC}"
    if ! validate_config "$config_file"; then
        echo -e "${RED}Configuration validation failed. Please check your config file.${NC}"
        return 1
    fi
    
    # Create temporary log file for detailed error output
    local log_file="/tmp/wireguard_connection_$(date +%s).log"
    
    # Connect using sudo with detailed error capture
    echo -e "${BLUE}Attempting connection...${NC}"
    if sudo wg-quick up "$config_file" 2>"$log_file"; then
        echo -e "${GREEN}Connected to $config_name${NC}"
        # Clean up log file on success
        rm -f "$log_file"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}Failed to connect to $config_name (Exit code: $exit_code)${NC}"
        
        # Display detailed error information
        if [ -f "$log_file" ]; then
            echo -e "${YELLOW}Error details:${NC}"
            while IFS= read -r line; do
                echo -e "${RED}  $line${NC}"
            done < "$log_file"
            
            # Provide specific troubleshooting based on common errors
            provide_troubleshooting_hints "$log_file"
            
            # Keep log file for user reference
            echo -e "${YELLOW}Full error log saved to: $log_file${NC}"
        fi
        
        echo -e "${YELLOW}The interface may already be active. Trying to disconnect first...${NC}"
        
        # Try to disconnect any existing interfaces first
        disconnect_from_config "$config_name" && sleep 2
        
        # Try to connect again
        echo -e "${BLUE}Trying to connect again...${NC}"
        if sudo wg-quick up "$config_file" 2>"$log_file"; then
            echo -e "${GREEN}Connected to $config_name${NC}"
            rm -f "$log_file"
            return 0
        else
            echo -e "${RED}Failed to connect to $config_name again.${NC}"
            if [ -f "$log_file" ]; then
                echo -e "${YELLOW}Second attempt error details:${NC}"
                while IFS= read -r line; do
                    echo -e "${RED}  $line${NC}"
                done < "$log_file"
            fi
            return 1
        fi
    fi
}

# Function to validate configuration file
validate_config() {
    local config_file="$1"
    local errors=0
    
    echo -e "${BLUE}Checking configuration syntax...${NC}"
    
    # Check if file exists and is readable
    if [ ! -r "$config_file" ]; then
        echo -e "${RED}  ✗ Configuration file is not readable${NC}"
        return 1
    fi
    
    # Check for required sections
    if ! grep -q "^\[Interface\]" "$config_file"; then
        echo -e "${RED}  ✗ Missing [Interface] section${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ [Interface] section found${NC}"
    fi
    
    if ! grep -q "^\[Peer\]" "$config_file"; then
        echo -e "${RED}  ✗ Missing [Peer] section${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ [Peer] section found${NC}"
    fi
    
    # Check for required Interface fields
    if ! grep -q "^PrivateKey" "$config_file"; then
        echo -e "${RED}  ✗ Missing PrivateKey in [Interface]${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ PrivateKey found${NC}"
    fi
    
    if ! grep -q "^Address" "$config_file"; then
        echo -e "${RED}  ✗ Missing Address in [Interface]${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Address found${NC}"
    fi
    
    # Check for required Peer fields
    if ! grep -q "^PublicKey" "$config_file"; then
        echo -e "${RED}  ✗ Missing PublicKey in [Peer]${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ PublicKey found${NC}"
    fi
    
    if ! grep -q "^Endpoint" "$config_file"; then
        echo -e "${RED}  ✗ Missing Endpoint in [Peer]${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Endpoint found${NC}"
        
        # Test endpoint connectivity
        local endpoint=$(grep "^Endpoint" "$config_file" | cut -d'=' -f2 | tr -d ' ')
        local host=$(echo "$endpoint" | cut -d':' -f1)
        local port=$(echo "$endpoint" | cut -d':' -f2)
        
        echo -e "${BLUE}Testing endpoint connectivity...${NC}"
        if nc -z -w5 "$host" "$port" 2>/dev/null; then
            echo -e "${GREEN}  ✓ Endpoint $endpoint is reachable${NC}"
        else
            echo -e "${YELLOW}  ⚠ Endpoint $endpoint may not be reachable${NC}"
            echo -e "${YELLOW}    This could be due to firewall or network issues${NC}"
        fi
    fi
    
    # Check file permissions
    local perms=$(stat -f "%OLp" "$config_file" 2>/dev/null || stat -c "%a" "$config_file" 2>/dev/null)
    if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        echo -e "${YELLOW}  ⚠ Configuration file permissions are $perms (recommended: 600)${NC}"
        echo -e "${YELLOW}    Run: chmod 600 '$config_file'${NC}"
    else
        echo -e "${GREEN}  ✓ File permissions are secure${NC}"
    fi
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}Configuration validation passed!${NC}"
        return 0
    else
        echo -e "${RED}Configuration validation failed with $errors error(s)${NC}"
        return 1
    fi
}

# Function to provide troubleshooting hints based on error patterns
provide_troubleshooting_hints() {
    local log_file="$1"
    
    if grep -q "Permission denied" "$log_file"; then
        echo -e "${YELLOW}Troubleshooting hint: Permission denied error${NC}"
        echo -e "${YELLOW}  Try: sudo chmod 600 ~/.wireguard/*.conf${NC}"
        echo -e "${YELLOW}  Or check if you need to run with different privileges${NC}"
    fi
    
    if grep -q "Address already in use" "$log_file"; then
        echo -e "${YELLOW}Troubleshooting hint: Address already in use${NC}"
        echo -e "${YELLOW}  Another VPN or WireGuard instance may be running${NC}"
        echo -e "${YELLOW}  Try disconnecting other VPNs first${NC}"
    fi
    
    if grep -q "Network is unreachable" "$log_file"; then
        echo -e "${YELLOW}Troubleshooting hint: Network unreachable${NC}"
        echo -e "${YELLOW}  Check your internet connection${NC}"
        echo -e "${YELLOW}  Verify the endpoint address and port${NC}"
    fi
    
    if grep -q "Invalid key" "$log_file"; then
        echo -e "${YELLOW}Troubleshooting hint: Invalid key error${NC}"
        echo -e "${YELLOW}  Check that your private/public keys are correct${NC}"
        echo -e "${YELLOW}  Keys should be 44 characters long and base64 encoded${NC}"
    fi
    
    if grep -q "RTNETLINK answers: File exists" "$log_file"; then
        echo -e "${YELLOW}Troubleshooting hint: Interface already exists${NC}"
        echo -e "${YELLOW}  Try disconnecting first, then reconnecting${NC}"
    fi
}

# Function to disconnect from a configuration
disconnect_from_config() {
    local config_name="$1"
    local config_file="$USER_CONFIG_DIR/$config_name"
    local config_base=$(basename "$config_name" .conf)
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Configuration file not found: $config_file${NC}"
        return 1
    fi
    
    # Check if currently connected
    if ! is_config_connected "$config_name"; then
        echo -e "${YELLOW}Not currently connected to $config_name.${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Disconnecting from $config_name...${NC}"
    
    # Find the specific interface for this configuration
    local interface=$(get_active_interface_for_config "$config_name")
    
    if [ -z "$interface" ]; then
        echo -e "${YELLOW}Could not find active interface for $config_name${NC}"
        # Fallback to trying the config file directly
        interface=""
    fi
    
    # Try the standard way first
    if sudo wg-quick down "$config_file" 2>/dev/null; then
        echo -e "${GREEN}Disconnected from $config_name${NC}"
        return 0
    fi
    
    # If that fails and we found a specific interface, try to disconnect it directly
    if [ -n "$interface" ]; then
        echo -e "${YELLOW}Trying to disconnect interface $interface directly...${NC}"
        if sudo wg-quick down "$interface" 2>/dev/null; then
            echo -e "${GREEN}Disconnected from $interface${NC}"
            return 0
        fi
    fi
    
    # Last resort: try to bring down the interface using ifconfig
    if [ -n "$interface" ]; then
        echo -e "${YELLOW}Trying to bring down interface using ifconfig...${NC}"
        if sudo ifconfig "$interface" down 2>/dev/null; then
            echo -e "${GREEN}Interface $interface brought down${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}Failed to disconnect from $config_name${NC}"
    return 1
}

# Function to list configurations
list_configs() {
    echo -e "${BLUE}Available configurations:${NC}"
    
    if [ -z "$(ls -A "$USER_CONFIG_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No configurations found.${NC}"
        return
    fi
    
    local i=1
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            config_name=$(basename "$config")
            if is_config_connected "$config_name"; then
                local interface=$(get_active_interface_for_config "$config_name")
                echo -e "${i}. ${GREEN}$config_name (CONNECTED - $interface)${NC}"
            else
                echo -e "${i}. $config_name"
            fi
            i=$((i+1))
        fi
    done
}

# Function to show detailed connection debug info (for troubleshooting)
show_connection_debug() {
    echo -e "${BLUE}Connection Debug Information${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    # Show all utun interfaces
    echo -e "${YELLOW}All utun interfaces:${NC}"
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        echo -e "  $iface"
    done
    
    # Show active WireGuard interfaces
    echo -e "${YELLOW}Active WireGuard interfaces:${NC}"
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            echo -e "${GREEN}  $iface (WireGuard active)${NC}"
            local peers=$(sudo wg show "$iface" peers 2>/dev/null)
            if [ -n "$peers" ]; then
                echo -e "${BLUE}    Peer: $peers${NC}"
            fi
        fi
    done
    
    # Show configuration file analysis
    echo -e "${YELLOW}Configuration file analysis:${NC}"
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            config_name=$(basename "$config")
            local public_key=$(grep "^PublicKey" "$config" | head -1 | cut -d'=' -f2 | tr -d ' ')
            echo -e "  $config_name:"
            echo -e "    PublicKey: $public_key"
            
            if is_config_connected "$config_name"; then
                local interface=$(get_active_interface_for_config "$config_name")
                echo -e "${GREEN}    Status: CONNECTED ($interface)${NC}"
            else
                echo -e "${RED}    Status: NOT CONNECTED${NC}"
            fi
        fi
    done
}

# Clear everything below metrics display
clear_below_metrics() {
    if $METRICS_ACTIVE; then
        # Save cursor position
        tput sc
        
        # Clear from menu start to end of screen
        tput cup "$MENU_START_LINE" 0
        tput ed
        
        # Restore cursor position to menu start
        tput cup "$MENU_START_LINE" 0
    else
        clear
    fi
}

# Function to get connection status summary
get_connection_status() {
    local interface=$(get_active_interface)
    
    if [ -z "$interface" ]; then
        # Count available configurations
        local config_count=0
        if [ -d "$USER_CONFIG_DIR" ]; then
            config_count=$(find "$USER_CONFIG_DIR" -name "*.conf" | wc -l | tr -d ' ')
        fi
        
        # Show system info when not connected
        local system_info=""
        if command -v uname &> /dev/null; then
            system_info=$(uname -s)
            if command -v hostname &> /dev/null; then
                system_info="$system_info @ $(hostname)"
            fi
        fi
        
        # Not connected message with configuration count
        local status_output="${RED}Not Connected${NC}"
        
        if [ "$config_count" -gt 0 ]; then
            status_output="$status_output | ${YELLOW}Available configs: $config_count${NC}"
        else
            status_output="$status_output | ${YELLOW}No configurations imported${NC}"
        fi
        
        if [ -n "$system_info" ]; then
            status_output="$status_output | ${BLUE}$system_info${NC}"
        fi
        
        echo -e "$status_output"
        return
    fi
    
    local config_name=$(get_active_config)
    if [ -z "$config_name" ]; then
        config_name="Unknown"
    fi
    
    local peer_count=0
    local transfer_info=""
    local formatted_transfer=""
    local handshake_info=""
    
    # Get peer count and basic transfer info
    if [ -n "$interface" ]; then
        peer_count=$(sudo wg show "$interface" peers 2>/dev/null | wc -l | tr -d ' ')
        transfer_info=$(sudo wg show "$interface" | grep "transfer" | head -1)
        handshake_info=$(sudo wg show "$interface" | grep "handshake" | head -1)
        
        # Format transfer info if available
        if [ -n "$transfer_info" ]; then
            # Extract sent and received data
            local sent=$(echo "$transfer_info" | grep -o "[0-9.]* KiB\|[0-9.]* MiB\|[0-9.]* GiB\|[0-9.]* B" | head -1)
            local received=$(echo "$transfer_info" | grep -o "[0-9.]* KiB\|[0-9.]* MiB\|[0-9.]* GiB\|[0-9.]* B" | tail -1)
            
            if [ -n "$sent" ] && [ -n "$received" ]; then
                formatted_transfer="↑${sent} ↓${received}"
            fi
        fi
        
        # Format handshake info if available
        if [ -n "$handshake_info" ]; then
            # Extract time like "1 minute ago" or similar
            local handshake_time=$(echo "$handshake_info" | grep -o "handshake: [^,]*" | sed 's/handshake: //')
            if [ -n "$handshake_time" ]; then
                handshake_info="Last handshake: ${handshake_time}"
            fi
        fi
    fi
    
    # Basic output
    local status_output="${GREEN}Connected${NC} | Interface: ${GREEN}$interface${NC} | Config: ${GREEN}$config_name${NC} | Peers: ${GREEN}$peer_count${NC}"
    
    # Add transfer info if available
    if [ -n "$formatted_transfer" ]; then
        status_output="$status_output | Transfer: ${GREEN}$formatted_transfer${NC}"
    fi
    
    # Add handshake info if available
    if [ -n "$handshake_info" ]; then
        status_output="$status_output\n${GREEN}$handshake_info${NC}"
    fi
    
    echo -e "$status_output"
}

# Display menu
display_menu() {
    if $METRICS_ACTIVE; then
        tput cup "$MENU_START_LINE" 0
    fi
    
    printf "${BLUE}══════════════════════════════════════${NC}\n"
    printf "${BLUE}   WireGuard Manager Script   ${NC}\n"
    printf "${BLUE}══════════════════════════════════════${NC}\n"
    
    # Add connection status if metrics aren't active
    if ! $METRICS_ACTIVE; then
        local connection_status=$(get_connection_status)
        printf "Status: %b\n" "$connection_status"
        printf "${BLUE}══════════════════════════════════════${NC}\n"
    fi
    
    printf "${YELLOW}1. Import WireGuard Configuration${NC}\n"
    printf "${YELLOW}2. Connect to a configuration${NC}\n"
    printf "${YELLOW}3. Disconnect from a configuration${NC}\n"
    printf "${YELLOW}4. List configurations${NC}\n"
    printf "${YELLOW}5. Toggle metrics display${NC}\n"
    printf "${YELLOW}6. Diagnostic tools${NC}\n"
    printf "${YELLOW}7. Quit${NC}\n"
    printf "${YELLOW}Select an option: ${NC}"
}

# Function to run diagnostic tools
run_diagnostics() {
    clear_below_metrics
    echo -e "${BLUE}WireGuard Diagnostic Tools${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    echo -e "${YELLOW}1. Test configuration file${NC}"
    echo -e "${YELLOW}2. Network connectivity test${NC}"
    echo -e "${YELLOW}3. DNS resolution test${NC}"
    echo -e "${YELLOW}4. System information${NC}"
    echo -e "${YELLOW}5. View connection logs${NC}"
    echo -e "${YELLOW}6. Fix permissions${NC}"
    echo -e "${YELLOW}7. Connection debug info${NC}"
    echo -e "${YELLOW}0. Back to main menu${NC}"
    echo -ne "${YELLOW}Select diagnostic option: ${NC}"
    read -r diag_option
    
    case $diag_option in
        1)
            test_configuration
            ;;
        2)
            test_network_connectivity
            ;;
        3)
            test_dns_resolution
            ;;
        4)
            show_system_info
            ;;
        5)
            view_connection_logs
            ;;
        6)
            fix_permissions
            ;;
        7)
            show_connection_debug
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac
    
    echo -e "${YELLOW}Press any key to continue...${NC}"
    read -n 1
}

# Function to test a specific configuration
test_configuration() {
    clear_below_metrics
    echo -e "${BLUE}Configuration File Test${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    list_configs
    
    if [ -z "$(ls -A "$USER_CONFIG_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}No configurations found to test.${NC}"
        return
    fi
    
    echo -ne "${YELLOW}Enter the number of the configuration to test (or 0 to cancel): ${NC}"
    read -r config_number
    
    if [ "$config_number" = "0" ]; then
        return
    fi
    
    local i=1
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            if [ "$i" = "$config_number" ]; then
                config_name=$(basename "$config")
                echo -e "${BLUE}Testing configuration: $config_name${NC}"
                validate_config "$config"
                return
            fi
            i=$((i+1))
        fi
    done
    
    echo -e "${RED}Invalid configuration number.${NC}"
}

# Function to test network connectivity
test_network_connectivity() {
    clear_below_metrics
    echo -e "${BLUE}Network Connectivity Test${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    # Test basic internet connectivity
    echo -e "${YELLOW}Testing basic internet connectivity...${NC}"
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Internet connectivity: OK${NC}"
    else
        echo -e "${RED}  ✗ Internet connectivity: FAILED${NC}"
        echo -e "${RED}    Check your network connection${NC}"
        return
    fi
    
    # Test DNS resolution
    echo -e "${YELLOW}Testing DNS resolution...${NC}"
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ DNS resolution: OK${NC}"
    else
        echo -e "${RED}  ✗ DNS resolution: FAILED${NC}"
    fi
    
    # Test endpoint connectivity for each config
    echo -e "${YELLOW}Testing WireGuard endpoints...${NC}"
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            config_name=$(basename "$config")
            if grep -q "^Endpoint" "$config"; then
                local endpoint=$(grep "^Endpoint" "$config" | cut -d'=' -f2 | tr -d ' ')
                local host=$(echo "$endpoint" | cut -d':' -f1)
                local port=$(echo "$endpoint" | cut -d':' -f2)
                
                echo -e "${BLUE}  Testing $config_name endpoint: $endpoint${NC}"
                if nc -z -w5 "$host" "$port" 2>/dev/null; then
                    echo -e "${GREEN}    ✓ Endpoint reachable${NC}"
                else
                    echo -e "${RED}    ✗ Endpoint unreachable${NC}"
                fi
            fi
        fi
    done
}

# Function to test DNS resolution
test_dns_resolution() {
    clear_below_metrics
    echo -e "${BLUE}DNS Resolution Test${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    local test_domains=("google.com" "cloudflare.com" "github.com")
    
    for domain in "${test_domains[@]}"; do
        echo -e "${YELLOW}Testing DNS resolution for $domain...${NC}"
        if nslookup "$domain" >/dev/null 2>&1; then
            local ip=$(nslookup "$domain" | grep "Address" | tail -1 | awk '{print $2}')
            echo -e "${GREEN}  ✓ $domain resolves to $ip${NC}"
        else
            echo -e "${RED}  ✗ Failed to resolve $domain${NC}"
        fi
    done
    
    # Check current DNS servers
    echo -e "${YELLOW}Current DNS servers:${NC}"
    if command -v scutil &> /dev/null; then
        scutil --dns | grep "nameserver" | head -5
    else
        cat /etc/resolv.conf | grep nameserver
    fi
}

# Function to show system information
show_system_info() {
    clear_below_metrics
    echo -e "${BLUE}System Information${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    echo -e "${YELLOW}Operating System:${NC}"
    sw_vers
    
    echo -e "${YELLOW}WireGuard Tools:${NC}"
    if command -v wg &> /dev/null; then
        echo -e "${GREEN}  wg: $(wg --version 2>&1 | head -1)${NC}"
    else
        echo -e "${RED}  wg: Not installed${NC}"
    fi
    
    if command -v wg-quick &> /dev/null; then
        echo -e "${GREEN}  wg-quick: Available${NC}"
    else
        echo -e "${RED}  wg-quick: Not available${NC}"
    fi
    
    echo -e "${YELLOW}Network Interfaces:${NC}"
    ifconfig -l | tr ' ' '\n' | while read -r iface; do
        if [[ "$iface" == utun* ]]; then
            echo -e "${GREEN}  $iface (potential WireGuard interface)${NC}"
        elif [[ "$iface" == en* ]] || [[ "$iface" == wi* ]]; then
            echo -e "${BLUE}  $iface (network interface)${NC}"
        fi
    done
    
    echo -e "${YELLOW}Active WireGuard Interfaces:${NC}"
    local found_wg=false
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            echo -e "${GREEN}  $iface${NC}"
            found_wg=true
        fi
    done
    
    if [ "$found_wg" = false ]; then
        echo -e "${YELLOW}  No active WireGuard interfaces${NC}"
    fi
}

# Function to view connection logs
view_connection_logs() {
    clear_below_metrics
    echo -e "${BLUE}Connection Logs${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    echo -e "${YELLOW}Recent WireGuard connection logs:${NC}"
    
    # Check for recent log files
    local log_files=$(find /tmp -name "wireguard_connection_*.log" -mtime -1 2>/dev/null)
    
    if [ -z "$log_files" ]; then
        echo -e "${YELLOW}No recent connection logs found.${NC}"
        echo -e "${YELLOW}Logs are created when connection attempts fail.${NC}"
    else
        echo "$log_files" | while read -r log_file; do
            if [ -f "$log_file" ]; then
                echo -e "${BLUE}Log file: $log_file${NC}"
                echo -e "${YELLOW}Contents:${NC}"
                cat "$log_file" | while IFS= read -r line; do
                    echo -e "${RED}  $line${NC}"
                done
                echo ""
            fi
        done
    fi
    
    # Show system logs related to WireGuard
    echo -e "${YELLOW}System logs (last 10 WireGuard-related entries):${NC}"
    if command -v log &> /dev/null; then
        log show --last 1h --predicate 'process CONTAINS "wireguard" OR eventMessage CONTAINS "wireguard"' --info 2>/dev/null | tail -10 || echo -e "${YELLOW}No system logs found${NC}"
    else
        echo -e "${YELLOW}System log viewing not available${NC}"
    fi
}

# Function to fix permissions
fix_permissions() {
    clear_below_metrics
    echo -e "${BLUE}Fix File Permissions${NC}"
    echo -e "${BLUE}══════════════════════════════════════${NC}"
    
    echo -e "${YELLOW}Checking and fixing WireGuard configuration permissions...${NC}"
    
    if [ ! -d "$USER_CONFIG_DIR" ]; then
        echo -e "${YELLOW}Creating configuration directory...${NC}"
        mkdir -p "$USER_CONFIG_DIR"
        chmod 700 "$USER_CONFIG_DIR"
        echo -e "${GREEN}  ✓ Created $USER_CONFIG_DIR${NC}"
    fi
    
    # Fix directory permissions
    chmod 700 "$USER_CONFIG_DIR"
    echo -e "${GREEN}  ✓ Set directory permissions to 700${NC}"
    
    # Fix configuration file permissions
    local fixed_count=0
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            local current_perms=$(stat -f "%OLp" "$config" 2>/dev/null || stat -c "%a" "$config" 2>/dev/null)
            if [ "$current_perms" != "600" ]; then
                chmod 600 "$config"
                echo -e "${GREEN}  ✓ Fixed permissions for $(basename "$config") ($current_perms → 600)${NC}"
                fixed_count=$((fixed_count + 1))
            else
                echo -e "${GREEN}  ✓ $(basename "$config") permissions already correct${NC}"
            fi
        fi
    done
    
    if [ $fixed_count -eq 0 ]; then
        echo -e "${GREEN}All permissions are already correct!${NC}"
    else
        echo -e "${GREEN}Fixed permissions for $fixed_count configuration file(s)${NC}"
    fi
}

# Function to toggle metrics display
toggle_metrics_display() {
    if $METRICS_ACTIVE; then
        stop_metrics_display
        clear
        echo -e "${YELLOW}Metrics display turned off.${NC}"
    else
        # Check if there's an active connection
        if interface=$(get_active_interface); then
            # We need to clear the screen before starting metrics
            clear
            start_metrics_display
            printf "${GREEN}Metrics display activated.${NC}\n"
        else
            printf "${RED}No active WireGuard connection. Cannot display metrics.${NC}\n"
        fi
    fi
}

# Process menu selection
process_menu_selection() {
    local option=$1
    
    case $option in
        1) 
            stop_metrics_display
            clear
            import_config
            # Return to menu automatically
            return
            ;;
        2)
            clear_below_metrics
            list_configs
            
            if [ -z "$(ls -A "$USER_CONFIG_DIR" 2>/dev/null)" ]; then
                # No configurations, wait 2 seconds then return
                sleep 2
                return
            fi
            
            echo -ne "${YELLOW}Enter the number of the configuration to connect to (or 0 to cancel): ${NC}"
            read -r config_number
            
            if [ "$config_number" = "0" ]; then
                return
            fi
            
            # Save current metrics state
            local was_metrics_active=$METRICS_ACTIVE
            
            # Stop metrics display during connection
            if $METRICS_ACTIVE; then
                stop_metrics_display
            fi
            
            # Connect to selected config
            local i=1
            for config in "$USER_CONFIG_DIR"/*.conf; do
                if [ -f "$config" ]; then
                    if [ "$i" = "$config_number" ]; then
                        config_name=$(basename "$config")
                        clear
                        connect_to_config "$config_name"
                        
                        # If successfully connected, start metrics
                        if is_config_connected "$config_name"; then
                            start_metrics_display
                        elif [ "$was_metrics_active" = true ] && interface=$(get_active_interface); then
                            # If metrics were active and another connection is still active
                            start_metrics_display
                        fi
                        
                        # Pause briefly to show output
                        sleep 1
                        return
                    fi
                    i=$((i+1))
                fi
            done
            
            if [ "$i" -le "$config_number" ]; then
                clear_below_metrics
                echo -e "${RED}Invalid configuration number.${NC}"
                sleep 2
            fi
            return
            ;;
        3)
            clear_below_metrics
            list_configs
            
            if [ -z "$(ls -A "$USER_CONFIG_DIR" 2>/dev/null)" ]; then
                # No configurations, wait 2 seconds then return
                sleep 2
                return
            fi
            
            echo -ne "${YELLOW}Enter the number of the configuration to disconnect from (or 0 to cancel): ${NC}"
            read -r config_number
            
            if [ "$config_number" = "0" ]; then
                return
            fi
            
            # Save current metrics state
            local was_metrics_active=$METRICS_ACTIVE
            
            # Stop metrics display during disconnection
            if $METRICS_ACTIVE; then
                stop_metrics_display
            fi
            
            # Disconnect from selected config
            local i=1
            local found=0
            for config in "$USER_CONFIG_DIR"/*.conf; do
                if [ -f "$config" ]; then
                    if [ "$i" = "$config_number" ]; then
                        found=1
                        config_name=$(basename "$config")
                        clear
                        disconnect_from_config "$config_name"
                        
                        # If metrics were active and another connection is still active
                        if [ "$was_metrics_active" = true ] && interface=$(get_active_interface); then
                            start_metrics_display
                        fi
                        
                        # Pause briefly to show output
                        sleep 1
                        return
                    fi
                    i=$((i+1))
                fi
            done
            
            if [ "$found" -eq 0 ]; then
                clear_below_metrics
                echo -e "${RED}Invalid configuration number.${NC}"
                sleep 2
            fi
            return
            ;;
        4)
            clear_below_metrics
            list_configs
            # Show the list for 3 seconds, then return
            sleep 3
            return
            ;;
        5)
            toggle_metrics_display
            # Pause briefly to show status message
            sleep 1
            return
            ;;
        6)
            run_diagnostics
            # Return to menu automatically
            return
            ;;
        7)
            stop_metrics_display
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            clear_below_metrics
            echo -e "${RED}Invalid option. Please try again.${NC}"
            sleep 1
            return
            ;;
    esac
}

# Main menu loop
main_menu() {
    while true; do
        # Display the menu
        if $METRICS_ACTIVE; then
            clear_below_metrics
        else
            clear
        fi
        
        display_menu
        read -r option
        
        # Process the selection
        process_menu_selection "$option"
        
        # No pause here - we return directly from process_menu_selection
    done
}

# Main function
main() {
    # Check if run as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please do not run this script as root.${NC}"
        exit 1
    fi
    
    # Set up trap to kill background processes on exit
    trap stop_metrics_display EXIT INT TERM
    
    # Clear screen
    clear
    
    # Check if any VPN is already connected and start metrics if so
    if interface=$(get_active_interface); then
        start_metrics_display
    fi
    
    # Start the main menu
    main_menu
}

# Run main function
main