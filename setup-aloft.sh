#!/bin/bash

# Aloft Dedicated Server Setup Script for Proxmox LXC
# This script sets up an Aloft dedicated server in a Proxmox LXC container
# Author: Claude
# Date: April 8, 2025

# Set script to exit on error
set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Display intro banner
echo -e "${GREEN}"
echo "  █████╗ ██╗      ██████╗ ███████╗████████╗"
echo " ██╔══██╗██║     ██╔═══██╗██╔════╝╚══██╔══╝"
echo " ███████║██║     ██║   ██║█████╗     ██║   "
echo " ██╔══██║██║     ██║   ██║██╔══╝     ██║   "
echo " ██║  ██║███████╗╚██████╔╝██║        ██║   "
echo " ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝        ╚═╝   "
echo " Dedicated Server Setup for Proxmox LXC"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]
  then error "Please run as root"
fi

# Configuration variables - edit these as needed
SERVER_USER="aloft"
INSTALL_DIR="/opt/aloft-server"
GAME_FILES_DIR="$INSTALL_DIR/game"
WINE_PREFIX="$INSTALL_DIR/wineprefix"
SAVE_DIR="$WINE_PREFIX/drive_c/users/$SERVER_USER/AppData/LocalLow/Astrolabe Interactive/Aloft/Data01/Saves"

# Default world configuration
DEFAULT_MAP_NAME="AloftWorld"
DEFAULT_ISLANDS=500
DEFAULT_CREATIVE=0 # 0 for survival, 1 for creative
DEFAULT_SERVER_NAME="AloftDedicatedServer"
DEFAULT_VISIBLE="true"
DEFAULT_PRIVATE="false"
DEFAULT_PLAYERS=8
DEFAULT_PORT=0 # 0 for automatic
DEFAULT_ADMIN=""

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    PKG_UPDATE="apt-get update"
    PKG_INSTALL="apt-get install -y"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    PKG_UPDATE="dnf check-update"
    PKG_INSTALL="dnf install -y"
else
    error "Unsupported package manager. This script requires apt or dnf."
fi

# Function to check if package is installed
is_installed() {
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        dpkg -l "$1" | grep -q ^ii
    else
        rpm -q "$1" &> /dev/null
    fi
}

# Function to create a systemd service for Aloft
create_systemd_service() {
    log "Creating systemd service for Aloft dedicated server"
    cat > /etc/systemd/system/aloft-server.service << EOF
[Unit]
Description=Aloft Dedicated Server
After=network.target

[Service]
Type=simple
User=$SERVER_USER
WorkingDirectory=$GAME_FILES_DIR
Environment="WINEPREFIX=$WINE_PREFIX"
Environment="WINEDEBUG=-all"
ExecStart=/bin/bash $INSTALL_DIR/start-server.sh
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log "Systemd service created"
}

# Function to create server start scripts
create_server_scripts() {
    log "Creating server management scripts"

    # Main start script
    cat > $INSTALL_DIR/start-server.sh << EOF
#!/bin/bash
cd $GAME_FILES_DIR

# Load configuration
source $INSTALL_DIR/server.conf

if [ "\$MODE" = "create" ]; then
    log_file="$INSTALL_DIR/logs/create-\$(date +%Y%m%d-%H%M%S).log"
    echo "Creating new world \$MAP_NAME with \$ISLANDS islands in \$CREATIVE mode"
    WINEDEBUG=-all WINEPREFIX=$WINE_PREFIX wine Aloft.exe -batchmode -nographics -server create#\$MAP_NAME#\$ISLANDS#\$CREATIVE# log#ERROR# disablevideo#true# > "\$log_file" 2>&1
    
    # After creating world, switch to load mode
    sed -i 's/MODE="create"/MODE="load"/' $INSTALL_DIR/server.conf
    
    # We need to restart after world creation
    echo "World created. Restarting server to load the world..."
    exec "\$0"
else
    log_file="$INSTALL_DIR/logs/server-\$(date +%Y%m%d-%H%M%S).log"
    echo "Loading world \$MAP_NAME with server name \$SERVER_NAME"
    echo "Server logs will be written to \$log_file"
    
    # Load existing world
    WINEDEBUG=-all WINEPREFIX=$WINE_PREFIX wine Aloft.exe -batchmode -nographics -server load#\$MAP_NAME# servername#\$SERVER_NAME# log#ERROR# isvisible#\$VISIBLE# privateislands#\$PRIVATE# playercount#\$PLAYERS# serverport#\$PORT# admin#\$ADMIN# disablevideo#true# > "\$log_file" 2>&1
fi
EOF

    # Configuration file
    cat > $INSTALL_DIR/server.conf << EOF
# Aloft Server Configuration
# Set MODE to "create" for first run, then it will auto-switch to "load"
MODE="create"

# World settings
MAP_NAME="$DEFAULT_MAP_NAME"
ISLANDS="$DEFAULT_ISLANDS"
CREATIVE="$DEFAULT_CREATIVE"

# Server settings
SERVER_NAME="$DEFAULT_SERVER_NAME"
VISIBLE="$DEFAULT_VISIBLE"
PRIVATE="$DEFAULT_PRIVATE"
PLAYERS="$DEFAULT_PLAYERS"
PORT="$DEFAULT_PORT"
ADMIN="$DEFAULT_ADMIN"
EOF

    # Management script
    cat > $INSTALL_DIR/manage-server.sh << EOF
#!/bin/bash
# Aloft Server Management Script

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_status() {
    if systemctl is-active --quiet aloft-server; then
        echo -e "\${GREEN}Server is running\${NC}"
        echo "Server logs are in $INSTALL_DIR/logs/"
        
        # Try to extract server code
        latest_log=\$(find $INSTALL_DIR/logs -name "server-*" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
        if [ -n "\$latest_log" ]; then
            code=\$(grep -o "Server code: [0-9]*" "\$latest_log" | tail -1 | cut -d' ' -f3)
            if [ -n "\$code" ]; then
                echo -e "\${GREEN}Server code: \${YELLOW}\$code\${NC}"
            else
                echo -e "\${YELLOW}Server code not found in logs yet\${NC}"
            fi
        fi
    else
        echo -e "\${RED}Server is not running\${NC}"
    fi
    
    echo -e "\${BLUE}Current configuration:\${NC}"
    grep -v "^#" $INSTALL_DIR/server.conf
}

case "\$1" in
    start)
        echo "Starting Aloft server..."
        systemctl start aloft-server
        ;;
    stop)
        echo "Stopping Aloft server..."
        systemctl stop aloft-server
        ;;
    restart)
        echo "Restarting Aloft server..."
        systemctl restart aloft-server
        ;;
    status)
        show_status
        ;;
    enable)
        echo "Enabling Aloft server to start at boot..."
        systemctl enable aloft-server
        ;;
    disable)
        echo "Disabling Aloft server auto-start..."
        systemctl disable aloft-server
        ;;
    create-world)
        echo "Setting server to create a new world on next start..."
        sed -i 's/MODE="load"/MODE="create"/' $INSTALL_DIR/server.conf
        echo "Restart the server to create a new world: sudo systemctl restart aloft-server"
        ;;
    config)
        echo "Opening server configuration in editor..."
        if [ -n "\$EDITOR" ]; then
            \$EDITOR $INSTALL_DIR/server.conf
        else
            nano $INSTALL_DIR/server.conf
        fi
        echo "Remember to restart the server after changing configuration: sudo systemctl restart aloft-server"
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|enable|disable|create-world|config}"
        exit 1
        ;;
esac
EOF

    # Set execute permissions
    chmod +x $INSTALL_DIR/start-server.sh
    chmod +x $INSTALL_DIR/manage-server.sh

    # Create symlink for easy access
    ln -sf $INSTALL_DIR/manage-server.sh /usr/local/bin/aloft-server

    log "Server scripts created"
}

# Main installation process
step "Checking system requirements"

log "Updating package repositories"
$PKG_UPDATE

log "Installing required packages"
$PKG_INSTALL sudo curl wget tar unzip software-properties-common gnupg2 cabextract xvfb libgdiplus libc6-dev

# Install Wine if not already installed
if ! command -v wine &> /dev/null; then
    step "Installing Wine"
    
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        # Add WineHQ repository
        wget -nc https://dl.winehq.org/wine-builds/winehq.key
        sudo apt-key add winehq.key
        
        # Detect Ubuntu/Debian version
        if [ -f /etc/debian_version ]; then
            if grep -q "Ubuntu" /etc/issue; then
                # Ubuntu
                UBUNTU_CODENAME=$(lsb_release -cs)
                sudo add-apt-repository "deb https://dl.winehq.org/wine-builds/ubuntu/ $UBUNTU_CODENAME main"
            else
                # Debian
                DEBIAN_VERSION=$(cat /etc/debian_version | cut -d'.' -f1)
                if [ "$DEBIAN_VERSION" = "10" ]; then
                    sudo add-apt-repository "deb https://dl.winehq.org/wine-builds/debian/ buster main"
                elif [ "$DEBIAN_VERSION" = "11" ]; then
                    sudo add-apt-repository "deb https://dl.winehq.org/wine-builds/debian/ bullseye main"
                else
                    sudo add-apt-repository "deb https://dl.winehq.org/wine-builds/debian/ bookworm main"
                fi
            fi
        fi
        
        sudo apt-get update
        sudo apt-get install -y --install-recommends winehq-stable
    else
        # RHEL/Fedora/CentOS
        sudo dnf config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/$(rpm -E %fedora)/winehq.repo
        sudo dnf install -y winehq-stable
    fi
    
    # Install winetricks
    log "Installing winetricks"
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    chmod +x winetricks
    sudo mv winetricks /usr/local/bin/
fi

step "Setting up server environment"

# Create server user
if ! id -u $SERVER_USER &>/dev/null; then
    log "Creating user $SERVER_USER"
    useradd -m -s /bin/bash $SERVER_USER
else
    log "User $SERVER_USER already exists"
fi

# Create installation directories
log "Creating installation directories"
mkdir -p $INSTALL_DIR/{game,logs,wineprefix}
chown -R $SERVER_USER:$SERVER_USER $INSTALL_DIR

step "Wine Configuration"

# Configure Wine prefix
log "Setting up Wine prefix"
su - $SERVER_USER -c "WINEPREFIX=$WINE_PREFIX WINEARCH=win64 wineboot -u"
su - $SERVER_USER -c "WINEPREFIX=$WINE_PREFIX winetricks -q vcrun2019 dotnet48"

step "Game Files Preparation"

echo
echo -e "${YELLOW}Important:${NC} You need to copy your Aloft game files to $GAME_FILES_DIR"
echo "This script does not download the game, as it requires a valid Steam purchase."
echo
echo "The most important files needed:"
echo "- Aloft.exe (Main game executable)"
echo "- All game data files and subdirectories"
echo
echo "After running this script, copy your game files with a command like:"
echo -e "${BLUE}cp -r /path/to/your/aloft/installation/* $GAME_FILES_DIR/${NC}"
echo

# Create server scripts
step "Creating server scripts and services"
create_server_scripts
create_systemd_service

# Set proper permissions
log "Setting proper permissions"
chown -R $SERVER_USER:$SERVER_USER $INSTALL_DIR

step "Installation Complete"

echo
echo -e "${GREEN}Aloft server setup is complete!${NC}"
echo
echo "What to do next:"
echo "1. Copy your Aloft game files to $GAME_FILES_DIR"
echo "2. Review and edit server configuration if needed:"
echo "   nano $INSTALL_DIR/server.conf"
echo
echo "Server management commands:"
echo "  aloft-server start    - Start the server"
echo "  aloft-server stop     - Stop the server"
echo "  aloft-server restart  - Restart the server"
echo "  aloft-server status   - Check server status and show join code"
echo "  aloft-server config   - Edit server configuration"
echo "  aloft-server enable   - Enable server auto-start at boot"
echo
echo "First time setup:"
echo "  The server will create a new world on first run"
echo "  After world creation, it will automatically switch to 'load' mode"
echo "  Server logs will be stored in $INSTALL_DIR/logs/"
echo "  Save files will be in $SAVE_DIR"
echo
echo -e "${YELLOW}Note:${NC} When the server first creates a world, it may take a few minutes"
echo "      The server room code will be shown when you run: aloft-server status"
echo

# Final tip
echo -e "${BLUE}To start your server now, run:${NC}"
echo "  aloft-server start"
echo
