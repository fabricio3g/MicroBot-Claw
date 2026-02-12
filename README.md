# MicroBot-Claw AI

AI-powered Telegram bot for OpenWrt routers. MicroPython implementation with Shell tool backends.

## Prerequisites

Before installing, connect to your router via SSH and install the required packages:

```bash
# SSH into router
ssh root@ROUTER_IP

# Install required packages
opkg update
opkg install curl micropython
opkg install curl micropython
```

## Deployment & Updates
See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions on how to copy files to your router and update the bot.

## Quick Start

```bash
# 1. Copy files to router (from your local machine)
scp -r microbot-ash root@ROUTER_IP:/root/

# 2. SSH into router
ssh root@ROUTER_IP

# 3. Run installer
cd /root/microbot-ash
chmod +x *.sh
./install.sh

# 4. Edit config
vi /data/config.json
```

## Running

### Manual (Foreground)
```bash
# Run with Python (recommended)
cd /root/microbot-ash
micropython microbot.py
```

### Background (Manual)
To keep it running after closing SSH:
```bash
cd /root/microbot-ash
nohup micropython microbot.py > /root/microbot.log 2>&1 &
```

### System Service (Auto-start)
1. Copy `microbot.init` to `/etc/init.d/microbot`
2. Make executable: `chmod +x /etc/init.d/microbot`
3. Enable: `/etc/init.d/microbot enable`
4. Start: `/etc/init.d/microbot start`

### View Logs
```bash
# Service logs
logread -f | grep microbot

# Manual logs
tail -f /root/microbot.log
```

## Configuration

Edit `/data/config.json`:

```json
{
    "tg_token": "YOUR_TELEGRAM_BOT_TOKEN",
    "provider": "openrouter",
    "openrouter_key": "YOUR_OPENROUTER_KEY",
    "openrouter_model": "anthropic/claude-opus-4"
}
```

Or for Anthropic:
```json
{
    "tg_token": "YOUR_TELEGRAM_BOT_TOKEN",
    "provider": "anthropic",
    "api_key": "YOUR_ANTHROPIC_KEY",
    "model": "claude-opus-4-5"
}
```

## Get API Keys

- **Telegram**: @BotFather on Telegram → `/newbot`
- **OpenRouter**: https://openrouter.ai/keys (works with Claude, GPT-4, Gemini, Llama)
- **Anthropic**: https://console.anthropic.com/ (Claude only)

## Bot Commands

| Command | Description |
|---------|-------------|
| `/start` | Start conversation |
| `/clear` | Clear history |

## Available Tools

| Tool | Description |
|------|-------------|
| `get_current_time` | Get date/time |
| `web_search` | Search web (needs search_key) |
| `scrape_web` | Fetch and extract text from URL |
| `read_file` | Read from /data/ |
| `write_file` | Write to /data/ |
| `edit_file` | Edit files |
| `list_dir` | List files |
| `system_info` | CPU, RAM, uptime |
| `network_status` | IP, WiFi, devices |
| `run_command` | Run shell commands |
| `get_weather` | Weather info |
| `set_schedule` | Create cron task |
| `list_schedules` | List scheduled tasks |
| `remove_schedule` | Remove scheduled task |
| `save_memory` | Save fact to long-term memory |
| `get_sys_health` | System health check |
| `get_wifi_status` | WiFi status |
| `get_exchange_rate` | Currency exchange rates |

## Example Queries

- "What's the system status?"
- "Show me connected network devices"
- "Run `logread | tail -20`"
- "What's the weather in Tokyo?"
- "Restart the firewall"
- "Write a note to /data/notes.txt"
- "Search for latest OpenWrt news"
- "Remind me every day at 9am to check logs"
- "Save that I prefer dark mode"

## Architecture

```
microbot.py (Python)
    │
    ├── LLMClient ────► OpenRouter / Anthropic API
    │
    ├── Agent (ReAct Loop)
    │   ├── Think  → Send to LLM
    │   ├── Act    → Detect & execute tool
    │   └── Observe → Feed result back
    │
    └── Tools ────────► Shell scripts (tools.sh)
                         │
                         ├── tool_web_search
                         ├── tool_system_info
                         ├── tool_run_command
                         └── ... (20+ tools)
```

## Files

```
/root/microbot-ash/
├── microbot.py      # Main Python entry (MicroPython)
├── microbot.init    # OpenWrt init script (service)
├── config.sh        # Config loader
├── tools.sh         # Tool functions (shell)
├── install.sh       # Installer
├── test.sh          # Test script
├── cron_task.sh     # Cron job runner
├── skills.sh        # Skill loader
└── plugins/         # Plugin modules
    ├── deep_search.sh
    └── ...

/data/
├── config.json      # Configuration
├── memory/          # Long-term memory
│   └── MEMORY.md
├── config/          # Personality files
│   ├── SOUL.md      # Bot personality
│   └── USER.md      # User profile
└── sessions/        # Chat history
```

## Requirements

- OpenWrt 21.02+
- **curl** - `opkg install curl`
- **micropython** - `opkg install micropython`
- wget (built-in)
- jsonfilter (built-in)

## Troubleshooting

```bash
# Test setup
./test.sh

# Debug Cron (Scheduling)
1. Check process: `ps | grep crond`
2. Check logs: `cat /tmp/cron_task.log`
3. Test task: `./cron_task.sh 123456 msg "Hello"`

# Test Telegram API
curl -k -s "https://api.telegram.org/botYOUR_TOKEN/getMe"

# Run manually for debugging
micropython microbot.py
```

## License

MIT
