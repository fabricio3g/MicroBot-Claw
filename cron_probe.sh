#!/bin/sh
# MicroBot Proactive Skill Runner
# Called by cron for "probe" type tasks.
# Runs a check command, evaluates result, and messages user ONLY if noteworthy.
#
# Usage: cron_probe.sh <chat_id> <skill_name> [args...]
#
# How it works:
#   1. Runs the probe command (defined by skill)
#   2. Sends result to the LLM with a compact prompt
#   3. If LLM says "ALERT:", sends that message to user
#   4. If LLM says "OK" or "SKIP", stays silent
#
# Dependencies: curl, jsonfilter, sh (all on OpenWrt)

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

CHAT_ID="$1"
SKILL_NAME="$2"
shift 2

[ -z "$CHAT_ID" ] || [ -z "$SKILL_NAME" ] && exit 1

# Find config
CONFIG=""
[ -f "/data/config.json" ] && CONFIG="/data/config.json"
[ -z "$CONFIG" ] && exit 1

# Load token and API creds
TG_TOKEN=""
OR_KEY=""
OR_MODEL=""
if command -v jsonfilter >/dev/null 2>&1; then
    TG_TOKEN=$(jsonfilter -i "$CONFIG" -e '@.tg_token' 2>/dev/null)
    OR_KEY=$(jsonfilter -i "$CONFIG" -e '@.openrouter_key' 2>/dev/null)
    OR_MODEL=$(jsonfilter -i "$CONFIG" -e '@.openrouter_model' 2>/dev/null)
fi
[ -z "$TG_TOKEN" ] && exit 1
[ -z "$OR_KEY" ] && exit 1
[ -z "$OR_MODEL" ] && OR_MODEL="anthropic/claude-opus-4"

# Script dir detection
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Send msg to Telegram
send_msg() {
    local text="$1"
    [ -z "$text" ] && return
    local safe=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
    safe=$(printf '%.4000s' "$safe")
    curl -k -s -m 10 \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":${CHAT_ID},\"text\":\"${safe}\"}" \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" >/dev/null 2>&1
}

# Run the probe command
probe_result=""
case "$SKILL_NAME" in
    disk_check)
        probe_result=$(df / | tail -1 | awk '{print "Root disk: "$3"/"$2" KB used ("$5" full), "$4" KB free"}')
        ;;
    mem_check)
        probe_result=$(free | grep Mem | awk '{printf "RAM: %dKB used / %dKB total (%dKB free)", $3, $2, $4}')
        ;;
    net_check)
        probe_result=$(ping -c 2 -W 3 8.8.8.8 2>&1 | tail -2)
        ;;
    load_check)
        probe_result="Load: $(cat /proc/loadavg | awk '{print $1", "$2", "$3}') | Uptime: $(cut -d. -f1 /proc/uptime)s"
        ;;
    service_check)
        probe_result=""
        for s in dnsmasq uhttpd dropbear; do
            if ! pidof "$s" >/dev/null 2>&1; then
                probe_result="${probe_result}${s}: DOWN! "
            fi
        done
        [ -z "$probe_result" ] && probe_result="All key services running (dnsmasq, uhttpd, dropbear)"
        ;;
    custom)
        # Custom probe: remaining args are the command
        probe_result=$(eval "$*" 2>&1 | head -c 2000)
        ;;
    *)
        exit 1
        ;;
esac

[ -z "$probe_result" ] && exit 0

# Ask LLM: is this worth alerting the user about?
# Use a tiny prompt and max_tokens to minimize API cost
eval_prompt="You are a system monitor. Given this data, respond with ONLY one of:
- ALERT: <short message for user> (if something needs attention)
- OK (if everything is normal)

Data: ${probe_result}"

# Build JSON request (inline, no temp files on disk)
req_body="{\"model\":\"${OR_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"$(printf '%s' "$eval_prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')\"}],\"max_tokens\":150}"

llm_response=$(printf '%s' "$req_body" | curl -k -s -m 30 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OR_KEY}" \
    -H "HTTP-Referer: https://microbot-ai" \
    -d @- \
    "https://openrouter.ai/api/v1/chat/completions" 2>/dev/null)

# Extract response text
reply=""
if command -v jsonfilter >/dev/null 2>&1; then
    reply=$(echo "$llm_response" | jsonfilter -e '@.choices[0].message.content' 2>/dev/null)
fi
# Fallback: grep
if [ -z "$reply" ]; then
    reply=$(echo "$llm_response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
fi

# Check if LLM wants to alert
case "$reply" in
    ALERT:*|alert:*)
        alert_msg=$(echo "$reply" | sed 's/^[Aa][Ll][Ee][Rr][Tt]:[[:space:]]*//')
        send_msg "⚠️ Proactive Alert: ${alert_msg}"
        ;;
    *)
        # OK or SKIP — stay silent
        ;;
esac
