#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  WireGuard Setup for Older macOS   ${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check macOS version
echo -e "${YELLOW}Checking macOS version...${NC}"
os_version=$(sw_vers -productVersion)
echo -e "Detected macOS version: ${GREEN}$os_version${NC}"

# Make the script executable
echo -e "${YELLOW}Making wireguard.sh executable...${NC}"
chmod +x wireguard.sh
echo -e "${GREEN}Done!${NC}"

# Check for Homebrew
echo -e "${YELLOW}Checking for Homebrew...${NC}"
if command -v brew &> /dev/null; then
    echo -e "${GREEN}Homebrew is installed.${NC}"
else
    echo -e "${RED}Homebrew is not installed.${NC}"
    echo -e "${YELLOW}Would you like to install Homebrew? (recommended) [y/n]${NC}"
    read -r install_brew
    if [[ "$install_brew" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Homebrew installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install Homebrew. Please install it manually.${NC}"
            echo "Visit: https://brew.sh/"
            exit 1
        fi
    else
        echo -e "${YELLOW}Skipping Homebrew installation. You will need to install WireGuard tools manually.${NC}"
    fi
fi

# Check for WireGuard tools
echo -e "${YELLOW}Checking for WireGuard tools...${NC}"
if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
    echo -e "${GREEN}WireGuard tools are already installed.${NC}"
else
    echo -e "${RED}WireGuard tools not found.${NC}"
    if command -v brew &> /dev/null; then
        echo -e "${YELLOW}Installing WireGuard tools with Homebrew...${NC}"
        brew install wireguard-tools
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}WireGuard tools installed successfully.${NC}"
        else
            echo -e "${RED}Failed to install WireGuard tools.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Please install the WireGuard tools manually.${NC}"
        echo "Visit: https://www.wireguard.com/install/"
        exit 1
    fi
fi

# Create configuration directory
echo -e "${YELLOW}Creating configuration directory...${NC}"
mkdir -p "$HOME/.wireguard"
echo -e "${GREEN}Created directory: $HOME/.wireguard${NC}"

# Final instructions
echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}Installation completed!${NC}"
echo -e "${YELLOW}To run the WireGuard manager:${NC}"
echo -e "${GREEN}./wireguard.sh${NC}"
echo -e ""
echo -e "${YELLOW}Need to import a configuration?${NC}"
echo -e "1. Run the script"
echo -e "2. Select option 1 from the menu"
echo -e "3. Provide the path to your .conf file"
echo -e "${BLUE}=====================================${NC}"

# Ask if user wants to run the script now
echo -e "${YELLOW}Would you like to run the WireGuard manager now? [y/n]${NC}"
read -r run_now
if [[ "$run_now" =~ ^[Yy]$ ]]; then
    ./wireguard.sh
fi 