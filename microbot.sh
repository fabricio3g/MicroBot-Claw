#!/bin/sh
# MicroBot AI - Main Entry Point (Ash/Shell Version)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source modules
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/telegram.sh"
. "${SCRIPT_DIR}/llm.sh"
. "${SCRIPT_DIR}/tools.sh"
. "${SCRIPT_DIR}/memory.sh"
. "${SCRIPT_DIR}/agent.sh"  # Import shared agent logic

echo "========================================"
echo "   MicroBot AI - OpenWrt AI Assistant"
echo "========================================"
echo ""

# Check config
if [ -z "$TG_TOKEN" ]; then
    echo "ERROR: No Telegram token configured"
    echo ""
    echo "Edit /data/config.json and add:"
    echo '  "tg_token": "YOUR_BOT_TOKEN"'
    exit 1
fi

api_key=$(get_api_key)
if [ -z "$api_key" ]; then
    echo "ERROR: No API key configured"
    exit 1
fi

# Initialize
echo "[main] Initializing memory..."
memory_init

echo "[main] Provider: $PROVIDER"
echo "[main] Model: $(get_current_model)"
echo "[main] Starting bot..."
echo ""

# Main loop
echo "[main] Entering main loop..."

while true; do
    # Get updates from Telegram
    resp=$(tg_get_updates)
    
    # Check for valid response
    if [ -z "$resp" ]; then
        sleep 2
        continue
    fi
    
    # Write response to temp file for processing
    echo "$resp" > "${TEMP_DIR}/tg_response.txt"
    
    # Check for messages
    if ! grep -q "MSG:" "${TEMP_DIR}/tg_response.txt"; then
        sleep 2
        continue
    fi
    
    # Process each message
    while IFS=':' read -r type chat_id username text; do
        [ "$type" != "MSG" ] && continue
        [ -z "$chat_id" ] && continue
        [ -z "$text" ] && continue
        
        echo ""
        echo "========================================"
        echo "[telegram] From: ${username} (${chat_id})"
        echo "[telegram] Text: ${text}"
        echo "========================================"
        
        # Handle commands
        case "$text" in
            /start)
                tg_send_message "$chat_id" "Hello! I'm MicroBot AI. How can I help?"
                continue
                ;;
            /clear|/reset)
                session_clear "$chat_id"
                tg_send_message "$chat_id" "Conversation cleared!"
                continue
                ;;
            /status)
                tg_send_message "$chat_id" "$(tool_system_info)"
                continue
                ;;
            /help)
                tg_send_message "$chat_id" "Commands: /start /clear /status /help"
                continue
                ;;
        esac
        
        # Send typing
        tg_send_action "$chat_id" "typing"
        
        # Process and respond using shared agent logic
        response=$(process_message "$chat_id" "$text")
        
        echo "[telegram] Response: ${response:0:100}..."
        tg_send_message "$chat_id" "$response"
        
    done < "${TEMP_DIR}/tg_response.txt"
    
    sleep 2
done
