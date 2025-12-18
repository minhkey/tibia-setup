#!/bin/bash
# Automated Tibia 7.7 Server Setup Script for Headless Debian 13
# This script downloads, compiles, and configures a complete Tibia 7.7 server
# Downloads demonax branch for tibia-game repository
# Usage: sudo ./setup_headless_demonax.sh

set -e  # Exit on error
set -u  # Exit on undefined variable

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

TIBIA_USER="tibia"
INSTALL_DIR="/opt/tibia"
TEMP_BUILD_DIR="/tmp/tibia-build-$$"

# Server Configuration
WORLD_NAME="Zanera"
WORLD_ID=1
SERVER_IP="0.0.0.0"  # Bind to all interfaces
GAME_PORT=7172
LOGIN_PORT=7171
QUERYMANAGER_PORT=7173
QUERYMANAGER_PASSWORD="a6glaf0c"
ENCODED_PASSWORD='nXE?/>j`'  # Encoded form for .tibia config

# Account Configuration
DEFAULT_ACCOUNT_NUMBER=111111
DEFAULT_ACCOUNT_EMAIL="@tibia"
DEFAULT_ACCOUNT_PASSWORD="tibia"
# Password hash for "tibia" (from z-999-initial-data.sql)
AUTH_HASH="206699cbc2fae1683118c873d746aa376049cb5923ef0980298bb7acbba527ec9e765668f7a338dffea34acf61a20efb654c1e9c62d35148dba2aeeef8dc7788"

# Character Configuration
CHAR_ID_KNIGHT=100001
CHAR_ID_PALADIN=100002
CHAR_ID_SORCERER=100003
CHAR_ID_DRUID=100004

# GitHub Repository URLs
REPO_QUERYMANAGER="https://github.com/minhkey/tibia-querymanager.git"
REPO_GAME="https://github.com/minhkey/tibia-game.git"
REPO_LOGIN="https://github.com/minhkey/tibia-login.git"
REPO_DATA="https://github.com/minhkey/demonax-data.git"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_step() {
    echo ""
    echo "=== $1 ==="
    echo ""
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 not found. Please install $2"
        exit 1
    fi
}

verify_file() {
    if [ ! -f "$1" ]; then
        echo "Error: Required file not found: $1"
        exit 1
    fi
}

verify_directory() {
    if [ ! -d "$1" ]; then
        echo "Error: Required directory not found: $1"
        exit 1
    fi
}

# Function to download and extract GitHub repository with optional branch
download_github_repo_branch() {
    local repo_name="$1"
    local branch="${2:-}"  # Optional branch name
    local repo_url="https://github.com/minhkey/${repo_name}"

    echo "Downloading ${repo_name}..."

    if [ -n "$branch" ]; then
        # Try specific branch
        echo "  Attempting to download branch: $branch"
        if curl -L -s -f "${repo_url}/archive/refs/heads/${branch}.tar.gz" -o "${repo_name}.tar.gz"; then
            echo "  Downloaded ${branch} branch"
        else
            echo "Error: Failed to download ${repo_name} branch: ${branch}"
            exit 1
        fi
    else
        # Try main branch first, then master
        if curl -L -s -f "${repo_url}/archive/refs/heads/main.tar.gz" -o "${repo_name}.tar.gz"; then
            echo "  Downloaded main branch"
        elif curl -L -s -f "${repo_url}/archive/refs/heads/master.tar.gz" -o "${repo_name}.tar.gz"; then
            echo "  Downloaded master branch"
        else
            echo "Error: Failed to download ${repo_name}"
            exit 1
        fi
    fi

    # Extract tarball
    tar -xzf "${repo_name}.tar.gz"

    # Rename extracted directory to remove branch suffix
    if [ -d "${repo_name}-${branch}" ]; then
        mv "${repo_name}-${branch}" "${repo_name}"
    elif [ -d "${repo_name}-main" ]; then
        mv "${repo_name}-main" "${repo_name}"
    elif [ -d "${repo_name}-master" ]; then
        mv "${repo_name}-master" "${repo_name}"
    else
        # Try to find any directory starting with repo_name-
        extracted_dir=$(find . -maxdepth 1 -type d -name "${repo_name}-*" | head -1)
        if [ -n "$extracted_dir" ]; then
            mv "$extracted_dir" "${repo_name}"
        else
            echo "Error: Could not find extracted directory for ${repo_name}"
            exit 1
        fi
    fi

    rm -f "${repo_name}.tar.gz"
    echo "✓ ${repo_name} downloaded and extracted"
}

# =============================================================================
# PHASE 1: VALIDATION & DEPENDENCIES
# =============================================================================

echo "=========================================="
echo "  Tibia 7.7 Headless Server Setup"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Error: This script must be run as root (use sudo)"
   exit 1
fi

# Game data now comes from demonax-data repository
echo "Game data will be sourced from demonax-data repository"
echo "Using demonax branch for tibia-game repository"
echo ""

print_step "Step 1/10: Installing system dependencies"

# Update system packages
apt update

# Install build dependencies
apt install -y \
    build-essential \
    g++ \
    gcc \
    make \
    curl \
    libssl-dev \
    sqlite3 \
    ufw \
    systemd \
    pkg-config \
    libboost-all-dev \
    zlib1g-dev

# Install runtime dependencies that might be needed by compiled binaries
apt install -y \
    libstdc++6 \
    libgcc-s1 \
    libssl3 \
    libcrypto3 \
    zlib1g \
    libboost-system1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-thread1.74.0 \
    libboost-program-options1.74.0

# Update library cache
ldconfig

echo "✓ Dependencies installed"

# =============================================================================
# PHASE 2: USER & DIRECTORY SETUP
# =============================================================================

print_step "Step 2/10: Creating user and directory structure"

# Create tibia service user
if ! id "$TIBIA_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash "$TIBIA_USER"
    echo "✓ Created user: $TIBIA_USER"
else
    echo "✓ User already exists: $TIBIA_USER"
fi

# Create directory structure
mkdir -p "$INSTALL_DIR"/{game,login,querymanager}
mkdir -p "$INSTALL_DIR/game"/{bin,dat,map,mon,npc,usr,log,save}

chown -R "$TIBIA_USER:$TIBIA_USER" "$INSTALL_DIR"
echo "✓ Directory structure created"

# =============================================================================
# PHASE 3: REPOSITORY DOWNLOAD & COMPILATION
# =============================================================================

print_step "Step 3/10: Downloading repositories"

mkdir -p "$TEMP_BUILD_DIR"
cd "$TEMP_BUILD_DIR"

# Download all repositories with specific branches
echo "Downloading repositories..."
download_github_repo_branch "tibia-querymanager" ""  # Default branch
download_github_repo_branch "tibia-game" "demonax"    # demonax branch
download_github_repo_branch "tibia-login" ""          # Default branch
download_github_repo_branch "demonax-data" ""         # Default branch

print_step "Compiling binaries"
echo "This may take several minutes..."

# Compile Query Manager
echo "Compiling Query Manager..."
cd "$TEMP_BUILD_DIR/tibia-querymanager"
make clean > /dev/null 2>&1 || true
if ! make -j$(nproc); then
    echo "Error: Query Manager compilation failed"
    exit 1
fi
verify_file "build/querymanager"
install -m 755 build/querymanager "$INSTALL_DIR/querymanager/querymanager"
verify_file "$INSTALL_DIR/querymanager/querymanager"
echo "✓ Query Manager compiled and installed"

# Compile Game Server (from demonax branch)
echo "Compiling Game Server (demonax branch)..."
cd "$TEMP_BUILD_DIR/tibia-game"
make clean > /dev/null 2>&1 || true
if ! make -j$(nproc); then
    echo "Error: Game Server compilation failed"
    echo "Checking for missing dependencies..."
    # Try to install additional development packages
    apt install -y libboost-all-dev zlib1g-dev libssl-dev
    if ! make -j$(nproc); then
        echo "Game Server compilation failed even with additional dependencies"
        exit 1
    fi
fi
verify_file "build/game"

# Test the binary for library dependencies
echo "Testing compiled binary..."
if ! ldd build/game 2>&1 | grep -q "not found"; then
    echo "✓ Binary has all library dependencies"
else
    echo "Warning: Binary has missing library dependencies:"
    ldd build/game 2>&1 | grep "not found"
    echo "Attempting to install missing runtime libraries..."
    # Try to install common missing libraries
    apt install -y libstdc++6 libgcc-s1 libssl3 libcrypto3 zlib1g libboost-system1.74.0 libboost-filesystem1.74.0
    ldconfig
fi

install -m 755 build/game "$INSTALL_DIR/game/bin/game"
verify_file "$INSTALL_DIR/game/bin/game"

# Verify binary is executable and has correct permissions
if [ ! -x "$INSTALL_DIR/game/bin/game" ]; then
    echo "Error: Installed binary is not executable"
    exit 1
fi
chown tibia:tibia "$INSTALL_DIR/game/bin/game"
echo "✓ Game Server compiled and installed"

# Copy RSA key to game directory (if exists in source)
if [ -f "tibia.pem" ]; then
    install -m 600 -o "$TIBIA_USER" -g "$TIBIA_USER" \
        tibia.pem "$INSTALL_DIR/game/tibia.pem"
    echo "✓ RSA key copied to game directory"
else
    echo "Warning: tibia.pem not found in tibia-game source directory"
fi

# Compile Login Server
echo "Compiling Login Server..."
cd "$TEMP_BUILD_DIR/tibia-login"
make clean > /dev/null 2>&1 || true
if ! make -j$(nproc); then
    echo "Error: Login Server compilation failed"
    exit 1
fi
verify_file "build/login"
install -m 755 build/login "$INSTALL_DIR/login/login"
verify_file "$INSTALL_DIR/login/login"
echo "✓ Login Server compiled and installed"

# Copy RSA key to login directory (use game's key if available)
if [ -f "$INSTALL_DIR/game/tibia.pem" ]; then
    install -m 600 -o "$TIBIA_USER" -g "$TIBIA_USER" \
        "$INSTALL_DIR/game/tibia.pem" "$INSTALL_DIR/login/tibia.pem"
    echo "✓ RSA key copied to login directory"
else
    echo "Warning: No RSA key available for login server"
fi

# =============================================================================
# PHASE 4: GAME DATA DEPLOYMENT
# =============================================================================

print_step "Step 4/10: Deploying game data"

echo "Copying game data from demonax-data repository..."

# Verify demonax-data/game exists
verify_directory "$TEMP_BUILD_DIR/demonax-data/game"

cd "$TEMP_BUILD_DIR/demonax-data/game"

# Copy all game data except map.tar.xz (will be extracted separately)
echo "Copying game data..."
find . -maxdepth 1 -mindepth 1 ! -name 'map.tar.xz' -exec cp -rp {} "$INSTALL_DIR/game/" \; 2>/dev/null || true

# Extract compressed map data if present
if [ -f "map.tar.xz" ]; then
    echo "Extracting compressed map data..."
    tar -xJf map.tar.xz -C "$INSTALL_DIR/game/"
    echo "✓ Map data extracted"
fi

# Set ownership
chown -R "$TIBIA_USER:$TIBIA_USER" "$INSTALL_DIR/game"
echo "✓ Game data deployed"

# =============================================================================
# PHASE 5: DATABASE INITIALIZATION
# =============================================================================

print_step "Step 5/10: Initializing database"

# Calculate premium end timestamp (20 years from now)
CURRENT_TIMESTAMP=$(date +%s)
PREMIUM_END=$((CURRENT_TIMESTAMP + (20 * 365 * 24 * 60 * 60)))

echo "Creating initialization SQL script..."

# Create init.sql with world, account, and characters
cat > "$TEMP_BUILD_DIR/init.sql" << EOF
-- Tibia 7.7 Headless Server Initialization
-- Created: $(date)

-- Insert World
INSERT INTO Worlds (WorldID, Name, Type, RebootTime, Host, Port, MaxPlayers,
                    PremiumPlayerBuffer, MaxNewbies, PremiumNewbieBuffer)
VALUES ($WORLD_ID, '$WORLD_NAME', 0, 5, '$SERVER_IP', $GAME_PORT, 1000, 100, 300, 100);

-- Insert Account with 20-year premium
INSERT INTO Accounts (AccountID, Email, Auth, PremiumEnd)
VALUES ($DEFAULT_ACCOUNT_NUMBER, '$DEFAULT_ACCOUNT_EMAIL',
        X'$AUTH_HASH', $PREMIUM_END);

-- Insert 4 Non-GM Characters
INSERT INTO Characters (WorldID, CharacterID, AccountID, Name, Sex, Level, Profession, Residence, LastLoginTime)
VALUES
    ($WORLD_ID, $CHAR_ID_KNIGHT, $DEFAULT_ACCOUNT_NUMBER, 'Test Knight', 1, 8, 'Knight', 'Thais', $CURRENT_TIMESTAMP),
    ($WORLD_ID, $CHAR_ID_PALADIN, $DEFAULT_ACCOUNT_NUMBER, 'Test Paladin', 1, 8, 'Paladin', 'Thais', $CURRENT_TIMESTAMP),
    ($WORLD_ID, $CHAR_ID_SORCERER, $DEFAULT_ACCOUNT_NUMBER, 'Test Sorcerer', 1, 8, 'Sorcerer', 'Thais', $CURRENT_TIMESTAMP),
    ($WORLD_ID, $CHAR_ID_DRUID, $DEFAULT_ACCOUNT_NUMBER, 'Test Druid', 1, 8, 'Druid', 'Thais', $CURRENT_TIMESTAMP);
EOF

# Initialize database
cd "$INSTALL_DIR/querymanager"

echo "Creating database schema..."
sudo -u "$TIBIA_USER" sqlite3 tibia.db < "$TEMP_BUILD_DIR/tibia-querymanager/sqlite/schema.sql"
echo "✓ Database schema created"

echo "Applying migrations..."
sudo -u "$TIBIA_USER" sqlite3 tibia.db < "$TEMP_BUILD_DIR/tibia-querymanager/sqlite/z-001-migrate-v01-to-v02.sql" 2>/dev/null || true
sudo -u "$TIBIA_USER" sqlite3 tibia.db < "$TEMP_BUILD_DIR/tibia-querymanager/sqlite/z-002-migrate-v02-to-v03.sql" 2>/dev/null || true
sudo -u "$TIBIA_USER" sqlite3 tibia.db < "$TEMP_BUILD_DIR/tibia-querymanager/sqlite/z-003-character-deaths-indexes.sql" 2>/dev/null || true
echo "✓ Migrations applied"

echo "Inserting initial data..."
sudo -u "$TIBIA_USER" sqlite3 tibia.db < "$TEMP_BUILD_DIR/init.sql"
echo "✓ Initial data inserted"

# Set database permissions
chmod 600 tibia.db
chown "$TIBIA_USER:$TIBIA_USER" tibia.db

echo "✓ Database initialized"
echo "  - Account: $DEFAULT_ACCOUNT_NUMBER / $DEFAULT_ACCOUNT_PASSWORD"
echo "  - Premium until: $(date -d @$PREMIUM_END '+%Y-%m-%d')"
echo "  - Characters: Test Knight, Test Paladin, Test Sorcerer, Test Druid"

# =============================================================================
# PHASE 6: CONFIGURATION FILES
# =============================================================================

print_step "Step 6/10: Creating configuration files"

# Query Manager configuration
cat > "$INSTALL_DIR/querymanager/config.cfg" << EOF
# Query Manager Configuration
# Generated: $(date)

# HostCache Config
MaxCachedHostNames              = 100
HostNameExpireTime              = 30m

# SQLite Config
SQLite.File                     = "tibia.db"
SQLite.MaxCachedStatements      = 100

# Connection Config
QueryManagerPort                = $QUERYMANAGER_PORT
QueryManagerPassword            = "$QUERYMANAGER_PASSWORD"
QueryWorkerThreads              = 1
QueryBufferSize                 = 1M
QueryMaxAttempts                = 3
MaxConnections                  = 25
MaxConnectionIdleTime           = 5m
EOF

chown "$TIBIA_USER:$TIBIA_USER" "$INSTALL_DIR/querymanager/config.cfg"
echo "✓ Query Manager config created"

# Game Server configuration
cat > "$INSTALL_DIR/game/.tibia" << EOF
# Demonax - Graphical Multi-User-Dungeon
# .tibia: Konfigurationsdatei (Game-Server)
# Generated: $(date)

# Verzeichnisse
BINPATH     = "$INSTALL_DIR/game/bin"
MAPPATH     = "$INSTALL_DIR/game/map"
DATAPATH    = "$INSTALL_DIR/game/dat"
USERPATH    = "$INSTALL_DIR/game/usr"
LOGPATH     = "$INSTALL_DIR/game/log"
SAVEPATH    = "$INSTALL_DIR/game/save"
MONSTERPATH = "$INSTALL_DIR/game/mon"
NPCPATH     = "$INSTALL_DIR/game/npc"

# SharedMemories
SHM = 10011

# DebugLevel
DebugLevel = 2

# Server-Takt
Beat = 50

# QueryManager
QueryManager = {("127.0.0.1",$QUERYMANAGER_PORT,"$ENCODED_PASSWORD"),("127.0.0.1",$QUERYMANAGER_PORT,"$ENCODED_PASSWORD"),("127.0.0.1",$QUERYMANAGER_PORT,"$ENCODED_PASSWORD"),("127.0.0.1",$QUERYMANAGER_PORT,"$ENCODED_PASSWORD")}

# Weltstatus
World = "$WORLD_NAME"
State = public
EOF

chown "$TIBIA_USER:$TIBIA_USER" "$INSTALL_DIR/game/.tibia"
echo "✓ Game Server config created"

# Login Server configuration
cat > "$INSTALL_DIR/login/config.cfg" << EOF
# Login Server Configuration
# Generated: $(date)

# Service Config
LoginPort            = $LOGIN_PORT
ConnectionTimeout    = 5s
MaxConnections       = 10
MaxStatusRecords     = 1024
MinStatusInterval    = 5m
QueryManagerHost     = "127.0.0.1"
QueryManagerPort     = $QUERYMANAGER_PORT
QueryManagerPassword = "$QUERYMANAGER_PASSWORD"

# Service Info
StatusWorld          = "$WORLD_NAME"
URL                  = ""
Location             = ""
ServerType           = "Tibia"
ServerVersion        = "7.7"
ClientVersion        = "7.7"
MOTD                 = "Welcome to Tibia 7.7 Test Server!"
EOF

chown "$TIBIA_USER:$TIBIA_USER" "$INSTALL_DIR/login/config.cfg"
echo "✓ Login Server config created"

# =============================================================================
# PHASE 7: SYSTEMD SERVICES
# =============================================================================

print_step "Step 7/10: Creating systemd service files"

# Query Manager service
cat > /etc/systemd/system/tibia-querymanager.service << EOF
[Unit]
Description=Tibia Query Manager
After=network.target
Wants=tibia-login.service tibia-game.service

[Service]
Type=simple
User=$TIBIA_USER
Group=$TIBIA_USER
ExecStart=$INSTALL_DIR/querymanager/querymanager
WorkingDirectory=$INSTALL_DIR/querymanager/
Restart=always
RestartSec=10
LimitCORE=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=%n

[Install]
WantedBy=multi-user.target
EOF
echo "✓ Query Manager service created"

# Game Server service
cat > /etc/systemd/system/tibia-game.service << EOF
[Unit]
Description=Tibia Game Server
After=network.target tibia-querymanager.service
Requires=tibia-querymanager.service

[Service]
Type=simple
User=$TIBIA_USER
Group=$TIBIA_USER
ExecStart=$INSTALL_DIR/game/bin/game
WorkingDirectory=$INSTALL_DIR/game
Restart=always
RestartSec=10
TimeoutStopSec=600
LimitCORE=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=%n

[Install]
WantedBy=multi-user.target
EOF
echo "✓ Game Server service created"

# Login Server service
cat > /etc/systemd/system/tibia-login.service << EOF
[Unit]
Description=Tibia Login Server
After=network.target tibia-querymanager.service
Requires=tibia-querymanager.service

[Service]
Type=simple
User=$TIBIA_USER
Group=$TIBIA_USER
ExecStart=$INSTALL_DIR/login/login
WorkingDirectory=$INSTALL_DIR/login/
Restart=always
RestartSec=10
LimitCORE=infinity
StandardOutput=journal
StandardError=journal
SyslogIdentifier=%n

[Install]
WantedBy=multi-user.target
EOF
echo "✓ Login Server service created"

# Reload systemd
systemctl daemon-reload
echo "✓ Systemd configuration reloaded"

# =============================================================================
# PHASE 8: FIREWALL CONFIGURATION
# =============================================================================

print_step "Step 8/10: Configuring firewall"

ufw allow $LOGIN_PORT/tcp comment 'Tibia Login Server'
ufw allow $GAME_PORT/tcp comment 'Tibia Game Server'
ufw allow 22/tcp comment 'SSH'

# Enable firewall if not already enabled
if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable
    echo "✓ Firewall enabled"
else
    echo "✓ Firewall already active"
fi

echo "✓ Firewall rules configured"

# =============================================================================
# PHASE 9: SERVICE STARTUP
# =============================================================================

print_step "Step 9/10: Starting services"

# Enable services for auto-start
systemctl enable tibia-querymanager.service > /dev/null 2>&1
systemctl enable tibia-game.service > /dev/null 2>&1
systemctl enable tibia-login.service > /dev/null 2>&1
echo "✓ Services enabled for auto-start"

# Start Query Manager first
echo "Starting Query Manager..."
systemctl start tibia-querymanager.service
sleep 3

# Verify Query Manager started
if systemctl is-active --quiet tibia-querymanager.service; then
    echo "✓ Query Manager is running"
else
    echo "✗ Query Manager failed to start"
    journalctl -u tibia-querymanager -n 20 --no-pager
    exit 1
fi

# Start Game Server
echo "Starting Game Server..."
systemctl start tibia-game.service
sleep 2

# Verify Game Server started
if systemctl is-active --quiet tibia-game.service; then
    echo "✓ Game Server is running"
else
    echo "✗ Game Server failed to start"
    echo "Checking binary and dependencies..."
    # Test the binary directly
    if [ -f "$INSTALL_DIR/game/bin/game" ]; then
        echo "Binary exists at: $INSTALL_DIR/game/bin/game"
        file "$INSTALL_DIR/game/bin/game"
        ldd "$INSTALL_DIR/game/bin/game" 2>&1 | grep -E "not found|error" || true
    fi
    journalctl -u tibia-game -n 20 --no-pager
    exit 1
fi

# Start Login Server
echo "Starting Login Server..."
systemctl start tibia-login.service
sleep 2

# Verify Login Server started
if systemctl is-active --quiet tibia-login.service; then
    echo "✓ Login Server is running"
else
    echo "✗ Login Server failed to start"
    journalctl -u tibia-login -n 20 --no-pager
    exit 1
fi

echo ""
echo "✓ All services started successfully"
echo ""

# Verify ports are listening
echo "Verifying listening ports..."
sleep 2
ss -tlnp | grep -E "($LOGIN_PORT|$GAME_PORT|$QUERYMANAGER_PORT)" || true
echo ""

# =============================================================================
# PHASE 10: CLEANUP & DOCUMENTATION
# =============================================================================

print_step "Step 10/10: Cleanup and finalization"

# Create admin helper script
cat > "$INSTALL_DIR/admin-console.sh" << 'ADMIN_EOF'
#!/bin/bash
# Tibia 7.7 Server Administration Helper

echo "=========================================="
echo "  Tibia 7.7 Server Administration"
echo "=========================================="
echo ""
echo "Service Status:"
echo "---------------"
systemctl status tibia-querymanager --no-pager | head -3
systemctl status tibia-game --no-pager | head -3
systemctl status tibia-login --no-pager | head -3
echo ""
echo "Useful Commands:"
echo "----------------"
echo "View query manager logs:  journalctl -u tibia-querymanager -f"
echo "View game server logs:    journalctl -u tibia-game -f"
echo "View login server logs:   journalctl -u tibia-login -f"
echo "Restart all services:     systemctl restart tibia-*"
echo "Stop all services:        systemctl stop tibia-*"
echo "Start all services:       systemctl start tibia-querymanager && sleep 3 && systemctl start tibia-game tibia-login"
echo ""
echo "Files:"
echo "------"
echo "Database:     /opt/tibia/querymanager/tibia.db"
echo "Game data:    /opt/tibia/game/"
echo "Game config:  /opt/tibia/game/.tibia"
echo "Logs:         /opt/tibia/game/log/"
echo ""
ADMIN_EOF

chmod +x "$INSTALL_DIR/admin-console.sh"
echo "✓ Admin console script created"

# Cleanup temporary files
echo "Cleaning up temporary files..."
rm -rf "$TEMP_BUILD_DIR"
echo "✓ Temporary files removed"

# Get server IP
SERVER_IP_ACTUAL=$(hostname -I | awk '{print $1}')

# Print completion message
cat << EOF
=========================================="
  Setup Complete!
=========================================="

Server Information:
-------------------
World Name:    $WORLD_NAME
Server IP:     $SERVER_IP_ACTUAL
Login Port:    $LOGIN_PORT
Game Port:     $GAME_PORT

Account Information:
--------------------
Account:       $DEFAULT_ACCOUNT_NUMBER
Password:      $DEFAULT_ACCOUNT_PASSWORD
Premium Until: $(date -d @$PREMIUM_END '+%Y-%m-%d')

Characters:
-----------
- Test Knight (Level 8, Knight)
- Test Paladin (Level 8, Paladin)
- Test Sorcerer (Level 8, Sorcerer)
- Test Druid (Level 8, Druid)

All characters start in Thais [32369,32241,7]

Service Management:
-------------------
View status:    systemctl status tibia-*
View logs:      journalctl -u tibia-querymanager -f
Restart all:    systemctl restart tibia-*
Stop all:       systemctl stop tibia-*

Admin Script:
-------------
Run: $INSTALL_DIR/admin-console.sh

Database:
---------
Location: $INSTALL_DIR/querymanager/tibia.db
Access:   sqlite3 $INSTALL_DIR/querymanager/tibia.db

To connect with Tibia 7.7 client:
----------------------------------
1. Patch client IP to point to: $SERVER_IP_ACTUAL
2. Use account: $DEFAULT_ACCOUNT_NUMBER
3. Use password: $DEFAULT_ACCOUNT_PASSWORD

=========================================="
EOF