#!/bin/sh
# MicroBot AI (Ash Shell) - OpenWrt Installer

set -e

INSTALL_DIR="/opt/microbot-ash"
DATA_DIR="/data"

echo "=========================================="
echo "  MicroBot AI (Shell) - OpenWrt Installer"
echo "=========================================="

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Install dependencies (minimal)
echo "[1/4] Checking dependencies..."
opkg update

if ! command -v wget >/dev/null 2>&1; then
    opkg install wget
fi

if ! command -v jsonfilter >/dev/null 2>&1; then
    opkg install jsonfilter
fi

# Create directories
echo "[2/4] Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR/config"
mkdir -p "$DATA_DIR/memory"
mkdir -p "$DATA_DIR/sessions"

# Copy files if running from source dir
echo "[3/4] Installing files..."
if [ -f "./microbot.sh" ]; then
    cp ./*.sh "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/*.sh
    
    # Copy config template if exists
    if [ -f "./data/config.json" ]; then
        cp ./data/config.json "$DATA_DIR/config.json.template"
    fi
else
    echo "Please copy all .sh files to $INSTALL_DIR/"
fi

# Create default config if not exists
if [ ! -f "$DATA_DIR/config.json" ]; then
    echo "[4/4] Creating default configuration..."
    cat > "$DATA_DIR/config.json" << 'EOF'
{
    "wifi_ssid": "",
    "wifi_pass": "",
    "tg_token": "",
    "provider": "openrouter",
    "api_key": "",
    "model": "claude-opus-4-5",
    "openrouter_key": "",
    "openrouter_model": "anthropic/claude-opus-4",
    "proxy_host": "",
    "proxy_port": "",
    "search_key": "",
    "http_port": "8080"
}
EOF
    echo "Created $DATA_DIR/config.json"
else
    echo "[4/4] Config file already exists, keeping it"
fi

# Create init.d service
echo "[5/5] Creating startup service..."
cat > /etc/init.d/microbot-ai << 'SVCEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh /opt/microbot-ash/microbot.sh
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall microbot.sh 2>/dev/null || true
}
SVCEOF

chmod +x /etc/init.d/microbot-ai
/etc/init.d/microbot-ai enable

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Config file: $DATA_DIR/config.json"
echo ""
echo "Edit with:"
echo "  vi $DATA_DIR/config.json"
echo ""
echo "Required fields:"
echo "  tg_token        - Telegram bot token from @BotFather"
echo "  openrouter_key  - OpenRouter API key (or api_key for Anthropic)"
echo ""
echo "Commands:"
echo "  Start:   /etc/init.d/microbot-ai start"
echo "  Stop:    /etc/init.d/microbot-ai stop"
echo "  Restart: /etc/init.d/microbot-ai restart"
echo "  Logs:    logread -f | grep microbot"
echo ""
echo "Or test directly:"
echo "  /opt/microbot-ash/microbot.sh"
echo ""
