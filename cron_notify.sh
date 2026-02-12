#!/bin/sh
# Legacy cron_notify.sh - kept for backward compatibility
# New schedules use cron_task.sh instead
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

CHAT_ID="$1"
shift
MESSAGE="$*"

[ -z "$CHAT_ID" ] || [ -z "$MESSAGE" ] && exit 1

CONFIG=""
[ -f "/data/config.json" ] && CONFIG="/data/config.json"
[ -z "$CONFIG" ] && exit 1

TG_TOKEN=""
if command -v jsonfilter >/dev/null 2>&1; then
    TG_TOKEN=$(jsonfilter -i "$CONFIG" -e '@.tg_token' 2>/dev/null)
fi
if [ -z "$TG_TOKEN" ]; then
    TG_TOKEN=$(grep -o '"tg_token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" | sed 's/.*"tg_token"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi
[ -z "$TG_TOKEN" ] && exit 1

SAFE_MSG=$(printf '%s' "$MESSAGE" | sed 's/\\/\\\\/g; s/"/\\"/g')
curl -k -s -m 10 \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":${CHAT_ID},\"text\":\"${SAFE_MSG}\"}" \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" >/dev/null 2>&1
