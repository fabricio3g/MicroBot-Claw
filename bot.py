#!/usr/bin/env python3
"""
Simple Telegram Bot for OpenWrt - handles API calls
Calls existing shell scripts for message processing
"""

import json
import subprocess
import time
import os
import sys

# Try importing requests
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    import urllib.request
    HAS_REQUESTS = False

BOT_TOKEN = None
UPDATE_OFFSET = 0

def load_config():
    global BOT_TOKEN
    config_path = "/data/config.json"

    with open(config_path, 'r') as f:
        config = json.load(f)

    BOT_TOKEN = config.get('tg_token', '')
    print(f"[bot] Token loaded: {BOT_TOKEN[:10]}...")

def api_request(url, data=None):
    """Make HTTP request to Telegram API"""
    if HAS_REQUESTS:
        try:
            if data:
                resp = requests.post(url, json=data, timeout=30)
            else:
                resp = requests.get(url, timeout=30)
            return resp.json()
        except Exception as e:
            print(f"[bot] Request error: {e}")
            return None
    else:
        try:
            if data:
                req = urllib.request.Request(
                    url,
                    data=json.dumps(data).encode(),
                    headers={'Content-Type': 'application/json'}
                )
            else:
                req = urllib.request.Request(url)

            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode())
        except Exception as e:
            print(f"[bot] Request error: {e}")
            return None

def get_updates():
    """Poll for new messages"""
    global UPDATE_OFFSET

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/getUpdates"
    data = {"offset": UPDATE_OFFSET, "timeout": 30, "allowed_updates": ["message"]}

    result = api_request(url, data)

    if not result or not result.get("ok"):
        return None

    updates = result.get("result", [])

    if not updates:
        return None

    # Get first update
    update = updates[0]
    UPDATE_OFFSET = update["update_id"] + 1

    return update

def send_message(chat_id, text):
    """Send message via Telegram"""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

    # First try with markdown
    data = {"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}
    result = api_request(url, data)

    # If markdown fails, retry without
    if not result or not result.get("ok"):
        data = {"chat_id": chat_id, "text": text}
        api_request(url, data)

    print(f"[bot] Sent: {text[:50]}...")

def call_shell_process(message):
    """Call the shell script to process message"""
    try:
        # Create a simple wrapper script call
        cmd = f'cd /root/microbot-ash && MESSAGE="{message}" sh process_wrapper.sh'
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=120
        )

        if result.returncode == 0:
            return result.stdout.strip()
        else:
            return f"Error processing request"

    except subprocess.TimeoutExpired:
        return "Request timed out"
    except Exception as e:
        return f"Error: {str(e)}"

def main():
    print("[bot] MicroBot Starting...")
    load_config()

    print("[bot] Polling for messages...")

    while True:
        try:
            update = get_updates()

            if update and "message" in update:
                msg = update["message"]
                chat_id = msg["chat"]["id"]
                text = msg.get("text", "")

                if not text:
                    continue

                user = msg.get("from", {})
                username = user.get("username", "user")

                print(f"\n[bot] From @{username}: {text}")

                # Handle simple commands
                if text == "/start":
                    send_message(chat_id, "Hello! I'm MicroBot. Send me a message!")
                    continue

                if text == "/help":
                    send_message(chat_id, "Commands: /start, /help\nJust send any message to chat!")
                    continue

                # Process with shell
                response = call_shell_process(text)
                send_message(chat_id, response)

        except KeyboardInterrupt:
            print("\n[bot] Stopping...")
            break
        except Exception as e:
            print(f"[bot] Error: {e}")

        time.sleep(2)

if __name__ == "__main__":
    main()
