#!/bin/sh
# MicroBot AI - Configuration for OpenWrt


# Determine data directory
if [ -d "/data" ]; then
    DATA_DIR="/data"
else
    # Fallback to local data dir relative to this script
    # We assume this script is in /root/microbot-ash or similar
    # If SCRIPT_DIR is set (by caller), use it
    if [ -n "$SCRIPT_DIR" ]; then
        DATA_DIR="${SCRIPT_DIR}/data"
    else
        DATA_DIR="./data"
    fi
fi

mkdir -p "$DATA_DIR"
CONFIG_FILE="${DATA_DIR}/config.json"

WIFI_SSID=""
WIFI_PASS=""
TG_TOKEN=""
PROVIDER="openrouter"
API_KEY=""
MODEL="claude-opus-4-5"
OPENROUTER_KEY=""
OPENROUTER_MODEL="anthropic/claude-opus-4"
PROXY_HOST=""
PROXY_PORT=""
SEARCH_KEY=""
HTTP_PORT="8080"
MAX_TOKENS="4096"

# JSON escape function
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/  */ /g'
}

# Load config using jsonfilter
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[config] Config file not found: $CONFIG_FILE"
        echo "[config] Creating default config..."
        mkdir -p /data
        cat > "$CONFIG_FILE" << 'DEFCONF'
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
DEFCONF
        echo "[config] Created $CONFIG_FILE - please edit with your keys"
        return 1
    fi
    
    # echo "[config] Loading from $CONFIG_FILE"
    
    local val
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.wifi_ssid' 2>/dev/null) && [ -n "$val" ] && WIFI_SSID="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.wifi_pass' 2>/dev/null) && [ -n "$val" ] && WIFI_PASS="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.tg_token' 2>/dev/null) && [ -n "$val" ] && TG_TOKEN="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.provider' 2>/dev/null) && [ -n "$val" ] && PROVIDER="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.api_key' 2>/dev/null) && [ -n "$val" ] && API_KEY="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.model' 2>/dev/null) && [ -n "$val" ] && MODEL="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.openrouter_key' 2>/dev/null) && [ -n "$val" ] && OPENROUTER_KEY="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.openrouter_model' 2>/dev/null) && [ -n "$val" ] && OPENROUTER_MODEL="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.proxy_host' 2>/dev/null) && [ -n "$val" ] && PROXY_HOST="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.proxy_port' 2>/dev/null) && [ -n "$val" ] && PROXY_PORT="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.search_key' 2>/dev/null) && [ -n "$val" ] && SEARCH_KEY="$val"
    val=$(jsonfilter -i "$CONFIG_FILE" -e '@.http_port' 2>/dev/null) && [ -n "$val" ] && HTTP_PORT="$val"
    
    [ -z "$PROVIDER" ] && PROVIDER="openrouter"
    [ -z "$MODEL" ] && MODEL="claude-opus-4-5"
    [ -z "$OPENROUTER_MODEL" ] && OPENROUTER_MODEL="anthropic/claude-opus-4"
    [ -z "$HTTP_PORT" ] && HTTP_PORT="8080"
    
    # echo "[config] Provider: $PROVIDER" >&2
    # echo "[config] Model: $(get_current_model)" >&2
    if [ -n "$TG_TOKEN" ]; then
        # echo "[config] Telegram: ${TG_TOKEN:0:10}..." >&2
        :
    fi
    if [ -n "$OPENROUTER_KEY" ]; then
        # echo "[config] OpenRouter: ${OPENROUTER_KEY:0:10}..." >&2
        :
    fi
    if [ -n "$API_KEY" ]; then
        # echo "[config] Anthropic: ${API_KEY:0:10}..." >&2
        :
    fi
}

get_current_model() {
    if [ "$PROVIDER" = "openrouter" ]; then
        echo "$OPENROUTER_MODEL"
    else
        echo "$MODEL"
    fi
}

get_api_key() {
    if [ "$PROVIDER" = "openrouter" ]; then
        echo "$OPENROUTER_KEY"
    else
        echo "$API_KEY"
    fi
}

# Load config on source
if [ -z "$CONFIG_LOADED" ]; then
    load_config >&2
    CONFIG_LOADED=1
fi
