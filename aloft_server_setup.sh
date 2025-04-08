#!/bin/bash
#
# Aloft Server Setup Script for Proxmox LXC with AMP
# This script will set up a complete Aloft dedicated server environment
# in a Proxmox LXC container using AMP (CubeCoders)
#

set -e  # Exit on error
LOG_FILE="aloft_setup.log"
STEAM_USERNAME=""  # Leave empty for anonymous login if possible

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root"
fi

# Create base directories
BASE_DIR="/opt/aloft_server"
STEAMCMD_DIR="$BASE_DIR/steamcmd"
GAME_DIR="$BASE_DIR/game"
WINE_PREFIX="$BASE_DIR/wine_prefix"
AMP_CONFIG_DIR="$BASE_DIR/amp_config"

log "Creating base directories..."
mkdir -p "$STEAMCMD_DIR" "$GAME_DIR" "$WINE_PREFIX" "$AMP_CONFIG_DIR"

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install dependencies
log "Installing dependencies..."
apt-get install -y wget curl software-properties-common gnupg sudo ca-certificates dirmngr unzip lib32gcc-s1 libsdl2-2.0-0 jq

# Install Wine
log "Installing Wine..."
dpkg --add-architecture i386
mkdir -pm755 /etc/apt/keyrings
wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bullseye/winehq-bullseye.sources
apt-get update -y
apt-get install -y --install-recommends winehq-stable

# Install SteamCMD
log "Installing SteamCMD..."
cd "$STEAMCMD_DIR"
curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

# Configure Wine
log "Setting up Wine environment..."
export WINEPREFIX="$WINE_PREFIX"
export WINEARCH=win64

# Install Winetricks for better Wine compatibility
cd "$BASE_DIR"
wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks
./winetricks -q dotnet48 vcrun2019

# Download Aloft from Steam with SteamCMD
log "Downloading Aloft from Steam (App ID: 1660080)..."
cd "$STEAMCMD_DIR"

STEAM_LOGIN_PARAMS="anonymous"
if [ -n "$STEAM_USERNAME" ]; then
    read -sp "Enter Steam password for $STEAM_USERNAME: " STEAM_PASSWORD
    echo
    STEAM_LOGIN_PARAMS="$STEAM_USERNAME $STEAM_PASSWORD"
fi

# Try to download with SteamCMD (might require Steam account)
./steamcmd.sh +login $STEAM_LOGIN_PARAMS +force_install_dir "$GAME_DIR" +app_update 1660080 validate +quit

# Check if download was successful
if [ ! -f "$GAME_DIR/Aloft.exe" ]; then
    warn "Could not download Aloft using SteamCMD. Manual game file copy will be required."
    mkdir -p "$GAME_DIR/manual_copy"
    echo "Please copy your Aloft game files to: $GAME_DIR/manual_copy"
    echo "Then run: cp -r $GAME_DIR/manual_copy/* $GAME_DIR/"
fi

# Create necessary AMP configuration files
log "Creating AMP configuration files..."

# Create GenericModule.kvp file
cat > "$AMP_CONFIG_DIR/GenericModule.kvp" << 'EOF'
[Application]
DisplayName=Aloft Dedicated Server
ApplicationIDCommandLineArgs=-batchmode -nographics -server {SERVERCMD}#{MAPNAME}#{ISLANDS}#{CREATIVE}# servername#{SERVERNAME}# log#ERROR# isvisible#{VISIBLE}# privateislands#{PRIVATE}# playercount#{PLAYERS}# serverport#{PORT}# admin#{ADMIN}# disablevideo#true#
WorkingDirectory=.
ApplicationID=./Wine64/bin/wine
UpdateSources=Steam
ApplicationIsModded=False
CommandLineArgs=Aloft.exe {{$FormattedArgs}}
SteamWorkshopDownloadLocation=
StartupExecutable=Aloft.exe

[Meta]
ConfigManifest=aloftconfig.json
MaintenanceFunction=SteamCMD
ConfigRoot=aloft
DisplayImageSource=steam:1660080
SupportsVOIP=False
KnownBadProcesses=
Platforms=Linux,Windows
MetaConfigManifest=aloftmetaconfig.json
InstanceDirectory=
ShowDownloadProgressScriptSources=
CustomSetupScript=
CustomPostStartupScript=
CustomPreBackupScript=
CustomPostBackupScript=
CustomPreShutdownScript=
CustomPreUpdateScript=
CustomPostUpdateScript=
DoesServerHaveUpdateValidation=False
SaveDirFormats=

[Console]
ConsoleSource=StdOut
RetainOnlyRegularOutput=False
ConsolePromptRegExp=^\s*>\s*
ConsoleOutputRegExp=^(.*)$
ConsoleParsers=AloftConsoleParser
LogTimeStampsFormat=
LogTimeStampsLength=
ForceUpdateTimestamps=
AnyTextParser=AloftConsoleParser
CommandRouting=Stdin
TimestampTriggerThorough=False
TimestampTriggerHalfways=False
TimestampTriggerDisable=True
ServerNameParser=
ServerNameReplacement=
ServerVersionParser=
ServerVersionReplacement=
ServerSoftwareParser=
ServerSoftwareReplacement=
ApplicationIDCommandParameters=
KillDelay=30

[SteamCMD]
SteamUser=
SteamLoginAnonymous=true
UseAnonymousCredentials=true
AppID=1660080

[AloftConsoleParser]
UserJoinedRegex=^(?<timestamp>\S+)\s(?<username>.+?) joined the game$
UserLeftRegex=^(?<timestamp>\S+)\s(?<username>.+?) left the game$
ChatRegex=^(?<timestamp>\S+)\s<(?<username>.+?)>\s(?<message>.+)$
ServerRoomCodeRegex=^Server code: (?<code>\d+)$
EOF

# Create aloftconfig.json file
cat > "$AMP_CONFIG_DIR/aloftconfig.json" << 'EOF'
{
  "SERVERCMD": {
    "DisplayName": "Server Mode",
    "Description": "Whether to create or load a world",
    "Type": "enum",
    "EnumValues": {
      "create": "Create New World",
      "load": "Load Existing World"
    },
    "Default": "load",
    "Category": "Server Configuration"
  },
  "MAPNAME": {
    "DisplayName": "Map Name",
    "Description": "Your map name (NO SPACES)",
    "Type": "string",
    "Default": "AloftWorld",
    "Category": "Server Configuration"
  },
  "ISLANDS": {
    "DisplayName": "Number of Islands",
    "Description": "Number of islands (e.g., 250, 500) - only used in create mode",
    "Type": "number",
    "Default": 500,
    "Category": "Server Configuration"
  },
  "CREATIVE": {
    "DisplayName": "Game Mode",
    "Description": "0 for survival, 1 for creative mode - only used in create mode",
    "Type": "enum",
    "EnumValues": {
      "0": "Survival",
      "1": "Creative"
    },
    "Default": "0",
    "Category": "Server Configuration"
  },
  "SERVERNAME": {
    "DisplayName": "Server Name",
    "Description": "Server name shown in-game (NO SPACES)",
    "Type": "string",
    "Default": "AloftServer",
    "Category": "Server Configuration"
  },
  "VISIBLE": {
    "DisplayName": "Server Visibility",
    "Description": "Show in server browser",
    "Type": "enum",
    "EnumValues": {
      "true": "Visible",
      "false": "Hidden"
    },
    "Default": "true",
    "Category": "Server Configuration"
  },
  "PRIVATE": {
    "DisplayName": "Private Islands",
    "Description": "Protected home island spawning",
    "Type": "enum",
    "EnumValues": {
      "true": "Enabled",
      "false": "Disabled"
    },
    "Default": "false",
    "Category": "Server Configuration"
  },
  "PLAYERS": {
    "DisplayName": "Max Players",
    "Description": "Maximum player count",
    "Type": "number",
    "Default": 8,
    "Category": "Server Configuration"
  },
  "PORT": {
    "DisplayName": "Server Port",
    "Description": "Server port (0 for automatic)",
    "Type": "number",
    "Default": 0,
    "Category": "Server Configuration"
  },
  "ADMIN": {
    "DisplayName": "Admin Steam IDs",
    "Description": "Steam IDs for admins (comma separated)",
    "Type": "string",
    "Default": "",
    "Category": "Server Configuration"
  }
}
EOF

# Create aloftmetaconfig.json file
cat > "$AMP_CONFIG_DIR/aloftmetaconfig.json" << 'EOF'
{
  "Meta": {
    "DisplayName": "Aloft Dedicated Server",
    "SupportsCustomFolders": true,
    "ConfigRoot": "aloft"
  }
}
EOF

# Create wrapper script for Aloft server
cat > "$GAME_DIR/run_aloft_server.sh" << 'EOF'
#!/bin/bash
# Wrapper script for Aloft server

WINE_PREFIX="/opt/aloft_server/wine_prefix"
export WINEPREFIX="$WINE_PREFIX"
export WINEARCH=win64
export WINEDEBUG=-all

# Run the Aloft server with the parameters passed from AMP
cd "$(dirname "$0")"
wine Aloft.exe "$@"

# Save the server code for easy access
ROOM_CODE=$(grep -o "Server code: [0-9]*" output.txt | tail -1 | cut -d' ' -f3)
if [ -n "$ROOM_CODE" ]; then
    echo "$ROOM_CODE" > ServerRoomCode.txt
    echo "Server room code: $ROOM_CODE saved to ServerRoomCode.txt"
fi
EOF

chmod +x "$GAME_DIR/run_aloft_server.sh"

# Install AMP if not already installed
log "Checking for AMP installation..."
if [ ! -f "/usr/local/bin/ampinstmgr" ]; then
    log "Installing AMP..."
    
    # Download and run the AMP installer
    cd "$BASE_DIR"
    curl -O https://cubecoders.com/AMPInstallation.sh
    chmod +x AMPInstallation.sh
    
    log "Running AMP installer..."
    echo "During the AMP installation, you will need to:"
    echo "1. Enter your AMP license key"
    echo "2. Choose installation options (recommend accepting defaults)"
    echo "3. Set up the admin username and password"
    echo ""
    read -p "Press Enter to continue with AMP installation..." 
    
    ./AMPInstallation.sh
    
    if [ ! -f "/usr/local/bin/ampinstmgr" ]; then
        error "AMP installation failed. Please check the logs and try again."
    fi
else
    log "AMP is already installed."
fi

# Create Aloft instance in AMP
log "Creating Aloft instance in AMP..."
# First, extract the URL and username from AMP config
AMP_URL=$(grep -oP "URL:\s*\K.*" /home/amp/.ampdata/instances/ADS01/Instance.xml | tr -d ' ')
AMP_USER=$(grep -oP "Username:\s*\K.*" /home/amp/.ampdata/instances/ADS01/Instance.xml | tr -d ' ')

echo "AMP is available at: $AMP_URL"
echo "AMP Username: $AMP_USER"
read -sp "Enter AMP password: " AMP_PASSWORD
echo

# Create Generic module instance for Aloft
log "Creating Generic module instance for Aloft..."
INSTANCE_ID=$(ampinstmgr createinstance Generic Aloft)

if [ -z "$INSTANCE_ID" ]; then
    error "Failed to create AMP instance for Aloft."
fi

log "Created Aloft instance with ID: $INSTANCE_ID"

# Copy configuration files to AMP instance
INSTANCE_DIR=$(find /home/amp/.ampdata/instances -type d -name "$INSTANCE_ID" 2>/dev/null)

if [ -z "$INSTANCE_DIR" ]; then
    log "Finding instance directory by name..."
    INSTANCE_DIR=$(find /home/amp/.ampdata/instances -name "Instance.xml" -exec grep -l "InstanceName=\"Aloft\"" {} \; | xargs dirname)
fi

if [ -z "$INSTANCE_DIR" ]; then
    error "Could not find the AMP instance directory for Aloft."
fi

log "Copying configuration files to AMP instance directory: $INSTANCE_DIR"
cp "$AMP_CONFIG_DIR/GenericModule.kvp" "$INSTANCE_DIR/"
cp "$AMP_CONFIG_DIR/aloftconfig.json" "$INSTANCE_DIR/"
cp "$AMP_CONFIG_DIR/aloftmetaconfig.json" "$INSTANCE_DIR/"

# Set file permissions
log "Setting correct file permissions..."
chown -R amp:amp "$BASE_DIR"
chown -R amp:amp "$INSTANCE_DIR"

# Restart AMP to apply changes
log "Restarting AMP..."
systemctl restart AMP

log "Setting up firewall rules..."
# Allow common ports used by Aloft/Steam
ufw allow 27015:27030/tcp
ufw allow 27015:27030/udp
ufw allow 27036:27037/tcp
ufw allow 27036:27037/udp

# Final instructions
log "Installation complete!"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Aloft Server Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Your Aloft server has been set up with the following details:"
echo ""
echo "- AMP URL: $AMP_URL"
echo "- AMP Username: $AMP_USER"
echo "- Aloft Instance ID: $INSTANCE_ID"
echo "- Game Directory: $GAME_DIR"
echo ""
echo "Next steps:"
echo "1. Log in to AMP at $AMP_URL"
echo "2. Go to the 'Instances' tab and select your Aloft server"
echo "3. Configure your server settings (map name, player count, etc.)"
echo "4. Start your server using the AMP controls"
echo ""
if [ ! -f "$GAME_DIR/Aloft.exe" ]; then
    echo -e "${YELLOW}IMPORTANT:${NC} You need to manually copy your Aloft game files!"
    echo "Copy your Aloft game files from Windows to: $GAME_DIR/manual_copy"
    echo "Then run: cp -r $GAME_DIR/manual_copy/* $GAME_DIR/"
    echo ""
fi
echo "Server logs will be available in the AMP interface."
echo "The server room code will be saved to $GAME_DIR/ServerRoomCode.txt when the server starts."
echo ""
echo -e "${BLUE}Enjoy your Aloft server!${NC}"
