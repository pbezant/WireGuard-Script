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
    local config_base=$(basename "$config_name" .conf)
    
    # Check if the interface is already up using ifconfig instead of wg show
    # First try with wg show
    if sudo wg show interfaces 2>/dev/null | grep -q "$config_base"; then
        return 0  # Already connected
    fi
    
    # Also check network interfaces (for macOS)
    if ifconfig | grep -q "utun" && sudo wg show 2>/dev/null | grep -q "interface"; then
        # Check if we can find the interface in wg
        for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
            if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
                return 0  # Found a WireGuard interface
            fi
        done
    fi
    
    return 1  # Not connected
}

# Function to get active wireguard interface
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
    for config in "$USER_CONFIG_DIR"/*.conf; do
        if [ -f "$config" ]; then
            config_name=$(basename "$config")
            if is_config_connected "$config_name"; then
                echo "$config_name"
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
    
    # Connect using sudo 
    if sudo wg-quick up "$config_file"; then
        echo -e "${GREEN}Connected to $config_name${NC}"
        return 0
    else
        echo -e "${RED}Failed to connect to $config_name. Error code: $?${NC}"
        echo -e "${YELLOW}The interface may already be active. Trying to disconnect first...${NC}"
        
        # Try to disconnect any existing interfaces first
        disconnect_from_config "$config_name" && sleep 2
        
        # Try to connect again
        echo -e "${BLUE}Trying to connect again...${NC}"
        if sudo wg-quick up "$config_file"; then
            echo -e "${GREEN}Connected to $config_name${NC}"
            return 0
        else
            echo -e "${RED}Failed to connect to $config_name again.${NC}"
            return 1
        fi
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
    
    # Before disconnecting, find the interface to disconnect
    local interface=""
    for iface in $(ifconfig -l | tr ' ' '\n' | grep utun); do
        if sudo wg show "$iface" 2>/dev/null | grep -q "interface"; then
            interface="$iface"
            break
        fi
    done
    
    # Try the standard way first
    if sudo wg-quick down "$config_file" 2>/dev/null; then
        echo -e "${GREEN}Disconnected from $config_name${NC}"
        return 0
    fi
    
    # If that fails, try to directly disconnect the interface we found
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
                echo -e "${i}. ${GREEN}$config_name (CONNECTED)${NC}"
            else
                echo -e "${i}. $config_name"
            fi
            i=$((i+1))
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
    printf "${YELLOW}6. Quit${NC}\n"
    printf "${YELLOW}Select an option: ${NC}"
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