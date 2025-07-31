#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

printf "${BLUE}=====================================${NC}\n"
printf "${BLUE}  WireGuard Setup for Older macOS   ${NC}\n"
printf "${BLUE}=====================================${NC}\n"

# Check macOS version
printf "${YELLOW}Checking macOS version...${NC}\n"
os_version=$(sw_vers -productVersion)
printf "Detected macOS version: ${GREEN}$os_version${NC}\n"

# Make the script executable
printf "${YELLOW}Making wireguard.sh executable...${NC}\n"
if [ -f "wireguard.sh" ]; then
    chmod +x wireguard.sh
    printf "${GREEN}Done!${NC}\n"
else
    printf "${RED}Error: wireguard.sh not found in current directory${NC}\n"
    printf "${YELLOW}Please make sure both install.sh and wireguard.sh are in the same directory${NC}\n"
    exit 1
fi

# Check for Homebrew
printf "${YELLOW}Checking for Homebrew...${NC}\n"
if command -v brew &> /dev/null; then
    printf "${GREEN}Homebrew is installed.${NC}\n"
else
    printf "${RED}Homebrew is not installed.${NC}\n"
    printf "${YELLOW}Would you like to install Homebrew? (recommended) [y/n]${NC}\n"
    read -r install_brew
    if [[ "$install_brew" =~ ^[Yy]$ ]]; then
        printf "${YELLOW}Installing Homebrew...${NC}\n"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ $? -eq 0 ]; then
            printf "${GREEN}Homebrew installed successfully.${NC}\n"
        else
            printf "${RED}Failed to install Homebrew. Please install it manually.${NC}\n"
            echo "Visit: https://brew.sh/"
            exit 1
        fi
    else
        printf "${YELLOW}Skipping Homebrew installation. You will need to install WireGuard tools manually.${NC}\n"
    fi
fi

# Check for WireGuard tools
printf "${YELLOW}Checking for WireGuard tools...${NC}\n"
if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
    printf "${GREEN}WireGuard tools are already installed.${NC}\n"
    wg_version=$(wg --version 2>&1 | head -1)
    printf "${GREEN}Version: $wg_version${NC}\n"
else
    printf "${RED}WireGuard tools not found.${NC}\n"
    if command -v brew &> /dev/null; then
        printf "${YELLOW}Installing WireGuard tools with Homebrew...${NC}\n"
        brew install wireguard-tools
        if [ $? -eq 0 ]; then
            printf "${GREEN}WireGuard tools installed successfully.${NC}\n"
            wg_version=$(wg --version 2>&1 | head -1)
            printf "${GREEN}Installed version: $wg_version${NC}\n"
        else
            printf "${RED}Failed to install WireGuard tools.${NC}\n"
            exit 1
        fi
    else
        printf "${RED}Please install the WireGuard tools manually.${NC}\n"
        echo "Visit: https://www.wireguard.com/install/"
        exit 1
    fi
fi

# Verify installation
printf "${YELLOW}Verifying installation...${NC}\n"
if command -v wg &> /dev/null && command -v wg-quick &> /dev/null; then
    printf "${GREEN}✓ WireGuard tools verified${NC}\n"
else
    printf "${RED}✗ WireGuard tools verification failed${NC}\n"
    exit 1
fi

# Check for netcat (needed for connectivity testing)
if ! command -v nc &> /dev/null; then
    printf "${YELLOW}Installing netcat for connectivity testing...${NC}\n"
    if command -v brew &> /dev/null; then
        brew install netcat
    else
        printf "${YELLOW}Netcat not found. Some diagnostic features may not work.${NC}\n"
    fi
fi

# Create configuration directory
printf "${YELLOW}Creating configuration directory...${NC}\n"
mkdir -p "$HOME/.wireguard"
chmod 700 "$HOME/.wireguard"
printf "${GREEN}Created directory: $HOME/.wireguard${NC}\n"

# Test basic functionality
printf "${YELLOW}Testing basic functionality...${NC}\n"
if sudo wg --version >/dev/null 2>&1; then
    printf "${GREEN}✓ WireGuard tools are working${NC}\n"
else
    printf "${RED}✗ WireGuard tools test failed${NC}\n"
    printf "${YELLOW}You may need to restart your terminal or check your PATH${NC}\n"
fi

# Final instructions
printf "${BLUE}=====================================${NC}\n"
printf "${GREEN}Installation completed!${NC}\n"
printf "${YELLOW}To run the WireGuard manager:${NC}\n"
printf "${GREEN}./wireguard.sh${NC}\n"
printf "\n"
printf "${YELLOW}Need to import a configuration?${NC}\n"
printf "1. Run the script\n"
printf "2. Select option 1 from the menu\n"
printf "3. Provide the path to your .conf file\n"
printf "${BLUE}=====================================${NC}\n"

# Ask if user wants to run the script now
printf "${YELLOW}Would you like to run the WireGuard manager now? [y/n]${NC}\n"
read -r run_now
if [[ "$run_now" =~ ^[Yy]$ ]]; then
    if [ -f "./wireguard.sh" ] && [ -x "./wireguard.sh" ]; then
        ./wireguard.sh
    else
        printf "${RED}Error: Cannot execute wireguard.sh${NC}\n"
        printf "${YELLOW}Please run: chmod +x wireguard.sh && ./wireguard.sh${NC}\n"
    fi
fi 