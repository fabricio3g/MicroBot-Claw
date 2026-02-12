#!/bin/sh
# MicroBot Cron Task Runner (called by crontab)
# Usage: cron_task.sh <chat_id> <type> <content...>
# Types:
#   msg <text>           - Send a fixed message
#   cmd <command>        - Run command, send output
#   url <url>            - Fetch URL, extract text, send summary
#   once_msg <id> <text> - Send message then remove schedule
#   once_cmd <id> <cmd>  - Run command then remove schedule

# Set PATH for cron (cron has minimal PATH)
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

CHAT_ID="$1"
TYPE="$2"
shift 2

[ -z "$CHAT_ID" ] || [ -z "$TYPE" ] && exit 1

# Find config + token
CONFIG=""
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_FILE="/tmp/cron_task.log"

log() {
    echo "$(date): $*" >> "$LOG_FILE"
}

log "Starting task: Type=$TYPE ID=$CHAT_ID Args=$*"

# Check multiple config locations
if [ -f "/data/config.json" ]; then
    CONFIG="/data/config.json"
elif [ -f "$SCRIPT_DIR/data/config.json" ]; then
    CONFIG="$SCRIPT_DIR/data/config.json"
elif [ -f "$SCRIPT_DIR/../data/config.json" ]; then
    CONFIG="$SCRIPT_DIR/../data/config.json"
fi

if [ -z "$CONFIG" ]; then
    log "Error: Config file not found"
    exit 1
fi

TG_TOKEN=""
if command -v jsonfilter >/dev/null 2>&1; then
    TG_TOKEN=$(jsonfilter -i "$CONFIG" -e '@.tg_token' 2>/dev/null)
fi
if [ -z "$TG_TOKEN" ]; then
    TG_TOKEN=$(grep -o '"tg_token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" | sed 's/.*"tg_token"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

if [ -z "$TG_TOKEN" ]; then
    log "Error: Token not found in $CONFIG"
    exit 1
fi

# Function: send message to Telegram
send_msg() {
    local text="$1"
    [ -z "$text" ] && return
    # Escape for JSON
    local safe=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    # Truncate to 4000 chars (Telegram limit)
    safe=$(printf '%.4000s' "$safe")
    curl -k -s -m 10 \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":${CHAT_ID},\"text\":\"${safe}\"}" \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" >/dev/null 2>&1
}

# Function: remove own schedule (for one-time tasks)
remove_self() {
    local sid="$1"
    [ -z "$sid" ] && return
    local ct="/tmp/.mb_cron_$$"
    crontab -l > "$ct" 2>/dev/null || return
    grep -v "#MICROBOT_ID=${sid}" "$ct" > "${ct}.n"
    if [ -s "${ct}.n" ]; then
        crontab "${ct}.n"
    else
        crontab -r 2>/dev/null
    fi
    rm -f "$ct" "${ct}.n"
}

# Dispatch by type
case "$TYPE" in
    msg)
        send_msg "$*"
        ;;
    cmd)
        result=$(eval "$*" 2>&1 | head -c 3000)
        send_msg "$result"
        ;;
    url)
        url="$1"
        result=$(curl -k -s -L -m 15 -A "Mozilla/5.0" "$url" 2>/dev/null | \
            sed 's/<script[^>]*>.*<\/script>//g; s/<style[^>]*>.*<\/style>//g; s/<[^>]*>/ /g' | \
            tr -s ' \t\n' ' ' | head -c 3000)
        if [ -n "$result" ]; then
            send_msg "Content from $url: $result"
        else
            send_msg "Error: Could not fetch $url"
        fi
        ;;
    once_msg)
        sched_id="$1"
        shift
        send_msg "$*"
        remove_self "$sched_id"
        ;;
    once_cmd)
        sched_id="$1"
        shift
        result=$(eval "$*" 2>&1 | head -c 3000)
        send_msg "$result"
        remove_self "$sched_id"
        ;;
    *)
        send_msg "Unknown task type: $TYPE"
        ;;
esac
