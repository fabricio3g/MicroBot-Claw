#!/usr/bin/env python3
"""
MicroBot AI - Telegram Bot for OpenWrt (MicroPython version)
# Compatible with limited Python environments (no subprocess, no requests)
"""

print("\n\n!!! STARTING MICROBOT V2 (UPDATED) !!!\n")
import sys


# Try to import u-modules (MicroPython), fallback to standard
try:
    import usys as sys
except ImportError:
    import sys

try:
    import uos as os
except ImportError:
    import os

try:
    import utime as time
except ImportError:
    import time

try:
    import ujson as json
except ImportError:
    import json

# --- MicroPython Compatibility Layer ---
# --- MicroPython Compatibility Layer ---
class OSPath:
    def join(self, *args):
        return "/".join([str(a).rstrip("/") for a in args])
        
    def dirname(self, path):
        path = str(path)
        if "/" not in path:
            return ""
        try:
            return path.rsplit("/", 1)[0]
        except:
            return ""
        
    def abspath(self, path):
        # Naive implementation
        if str(path).startswith("/"):
            return path
        return "/root/microbot-ash/" + str(path)
        
    def exists(self, path):
        try:
            os.stat(path)
            return True
        except:
            return False
            
Path = OSPath()

# Use standard os.path if available, otherwise use our polyfill
if hasattr(os, 'path'):
    Path = os.path

# Use standard os.path if available, otherwise use our polyfill
if hasattr(os, 'path'):
    Path = os.path

# Safe access to os.name
def get_os_name():
    try:
        return os.name
    except:
        return 'posix'

# Safe access to os.getenv
def get_env(key, default=None):
    try:
        return os.getenv(key, default)
    except:
        return default

# ---------------------------------------

# Configuration
# Determine script directory
try:
    SCRIPT_DIR = Path.dirname(Path.abspath(__file__))
except:
    SCRIPT_DIR = "/root/microbot-ash"
    
print("DEBUG: SCRIPT_DIR=" + SCRIPT_DIR)

# Check for config file in multiple locations
possible_configs = [
    "/data/config.json",
    Path.join(SCRIPT_DIR, "data", "config.json"),
    "data/config.json"
]

CONFIG_FILE = "/data/config.json" # Default
found_config = False
for p in possible_configs:
    print("DEBUG: Checking config at " + p)
    try:
        # os.stat works on both unix/windows for file existence
        os.stat(p)
        CONFIG_FILE = p
        found_config = True
        print("DEBUG: Found config at " + p)
        break
    except:
        pass

if not found_config:
    print("WARNING: Config file not found in searched paths")

TEMP_DIR = "/tmp/microbot"

# Ensure temp dir exists (handle Windows behavior)
is_windows = False
if get_os_name() == 'nt':
    is_windows = True

if is_windows:
    temp_base = get_env('TEMP', 'C:\\Temp')
    TEMP_DIR = Path.join(temp_base, 'microbot')
else:
    # OpenWrt/Linux/MicroPython
    if not Path.exists(TEMP_DIR):
        try:
            os.mkdir(TEMP_DIR)
        except:
            pass
            
if not Path.exists(TEMP_DIR):
    try:
        os.makedirs(TEMP_DIR)
    except:
        pass

def run_command(cmd):
    """Run shell command and return output. Uses os.popen or os.system fallback for MicroPython."""
    # Try os.popen first (standard Python)
    if hasattr(os, 'popen'):
        try:
            p = os.popen(cmd)
            result = p.read()
            p.close()
            return result.strip()
        except:
            pass
            
    # Fallback for MicroPython: use os.system and a temp file
    # We use a timestamped file in TEMP_DIR
    tmp_file = Path.join(TEMP_DIR, "cmd_out_" + str(int(time.time())) + ".txt")
    try:
        # Redirect stdout and stderr to temp file
        os.system(cmd + " > " + tmp_file + " 2>&1")
        
        # Read result
        result = ""
        if Path.exists(tmp_file):
            with open(tmp_file, 'r') as f:
                result = f.read()
            # Clean up temp file
            try:
                os.remove(tmp_file)
            except:
                pass
        return result.strip()
    except Exception as e:
        print("run_command error: " + str(e))
        return ""

def get_config_value(key):
    """Read config value using proper JSON parser if possible, or simple grep"""
    if Path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                data = json.load(f)
                return data.get(key)
        except:
            print("Error loading config json")
    return None

    return None

def urlencode(s):
    """Simple urlencode for MicroPython"""
    res = ""
    for c in str(s):
        if ('a' <= c <= 'z') or ('A' <= c <= 'Z') or ('0' <= c <= '9') or c in "-_.~":
            res += c
        else:
            # Simple manual formatting for hex without zfill
            code = ord(c)
            h = hex(code)[2:].upper()
            if len(h) < 2:
                h = "0" + h
            res += "%" + h
    return res

# --- LLM Client ---
class LLMClient:
    def __init__(self, config):
        self.config = config
        self.provider = config.get("provider", "openrouter")
        self.api_key = config.get("api_key", "")
        self.model = config.get("model", "claude-opus-4-5")
        self.or_key = config.get("openrouter_key", "")
        self.or_model = config.get("openrouter_model", "anthropic/claude-opus-4")
        self.max_tokens = int(config.get("max_tokens", 1024))
        
    def chat(self, messages, system_prompt=None):
        """Send chat request and return response dict"""
        url = ""
        headers = []
        data = {}
        
        if self.provider == "openrouter":
            url = "https://openrouter.ai/api/v1/chat/completions"
            headers = [
                "Content-Type: application/json",
                "Authorization: Bearer " + self.or_key,
                "HTTP-Referer: https://microbot-ai",
                "X-Title: MicroBot AI"
            ]
            
            # OpenRouter format: system prompt is a message
            msgs = []
            if system_prompt:
                msgs.append({"role": "system", "content": system_prompt})
            msgs.extend(messages)
            
            data = {
                "model": self.or_model,
                "messages": msgs,
                "max_tokens": self.max_tokens
            }
        else:
            # Anthropic
            url = "https://api.anthropic.com/v1/messages"
            headers = [
                "Content-Type: application/json",
                "x-api-key: " + self.api_key,
                "anthropic-version: 2023-06-01"
            ]
            
            data = {
                "model": self.model,
                "messages": messages,
                "max_tokens": self.max_tokens
            }
            if system_prompt:
                data["system"] = system_prompt
                
        # Serialize JSON
        try:
            body = json.dumps(data)
        except Exception as e:
            print("Error serializing request: " + str(e))
            return None
            
        # Write body to temp file in RAM (/tmp) to avoid shell limits
        req_file = Path.join(TEMP_DIR, "mimi_req_" + str(int(time.time())) + ".json")
        try:
            with open(req_file, 'w') as f:
                f.write(body)
        except Exception as e:
            print("Error writing request file: " + str(e))
            return None

        # Build curl command using the file
        header_args = ""
        for h in headers:
            header_args += " -H '" + h + "'"
            
        # Check proxy
        proxy = self.config.get("proxy_host")
        proxy_port = self.config.get("proxy_port")
        proxy_arg = ""
        if proxy and proxy_port:
            proxy_arg = " -x \"http://" + proxy + ":" + str(proxy_port) + "\""
            
        cmd = "curl -k -s -m 60" + proxy_arg + header_args + " -d @" + req_file + " '" + url + "'"
        
        resp_txt = run_command(cmd)
        
        # Cleanup temp file
        try:
            os.remove(req_file)
        except:
            pass
            
        if not resp_txt:
            print("Error: Empty LLM response (check connection or model status)")
            return None
            
        # print("DEBUG: Raw Response Start: " + resp_txt) # Slices can fail on some MicroPython builds
            
        try:
            return json.loads(resp_txt)
        except Exception as e:
            print("Error parsing LLM response: " + str(e))
            print("Full Raw Response: " + resp_txt) # Print full for debug
            return None

# --- Text cleanup for Telegram ---
def html_escape(text):
    """Simple HTML escape for Telegram"""
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def strip_markdown(text):
    """Remove markdown formatting so Telegram gets clean plain text"""
    s = str(text)
    # Remove bold/italic markers
    while "**" in s:
        s = s.replace("**", "")
    while "__" in s:
        s = s.replace("__", "")
    # Remove heading markers
    lines = s.split("\n")
    cleaned = []
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("### "):
            line = stripped[4:]
        elif stripped.startswith("## "):
            line = stripped[3:]
        elif stripped.startswith("# "):
            line = stripped[2:]
        # Remove bullet dashes at start (keep content)
        if stripped.startswith("- "):
            line = "  " + stripped[2:]
        cleaned.append(line)
    s = "\n".join(cleaned)
    # Remove code block markers
    while "```" in s:
        s = s.replace("```", "")
    while "`" in s:
        s = s.replace("`", "")
    return s

# --- Agent Logic ---
class Agent:
    def __init__(self, config):
        self.config = config
        self.llm = LLMClient(config)
        self.history = {} # chat_id -> [messages]
        self.max_history = 10
        self.token = config.get("tg_token")
        
    def get_history(self, chat_id):
        return self.history.get(chat_id, [])
        
    def add_to_history(self, chat_id, role, content):
        if chat_id not in self.history:
            self.history[chat_id] = []
        self.history[chat_id].append({"role": role, "content": content})
        # Keep last 10 turns (20 messages)
        while len(self.history[chat_id]) > 20:
            self.history[chat_id].pop(0)
            
    def clear_history(self, chat_id):
        self.history[chat_id] = []
        
    # All known tool names for detection (hardcoded defaults always present)
    KNOWN_TOOLS = [
        "web_search", "scrape_web", "get_current_time", "read_file", "write_file",
        "edit_file", "list_dir", "system_info", "network_status", "run_command",
        "list_services", "restart_service", "get_weather", "http_request",
        "set_schedule", "list_schedules", "remove_schedule", "save_memory",
        "get_sys_health", "get_wifi_status", "get_exchange_rate",
        "set_probe", "deep_search"
    ]

    # Cached tool descriptions (populated by load_skills at startup)
    _cached_tool_desc = ""

    @staticmethod
    def load_skills():
        """Try to load extra plugin tools from skills.sh.
        This ONLY adds new tools on top of the hardcoded defaults.
        If it fails, the bot works perfectly with the hardcoded list."""
        try:
            cmd = "cd " + SCRIPT_DIR + " && . ./config.sh && . ./skills.sh && skill_list_names"
            result = run_command(cmd)
            if result:
                for name in result.split("\n"):
                    name = name.strip()
                    if name and name not in Agent.KNOWN_TOOLS:
                        Agent.KNOWN_TOOLS.append(name)
                print("[skills] " + str(len(Agent.KNOWN_TOOLS)) + " tools available")

            # Cache descriptions for prompt
            desc_cmd = "cd " + SCRIPT_DIR + " && . ./config.sh && . ./skills.sh && skill_list_descriptions"
            desc_result = run_command(desc_cmd)
            if desc_result and len(desc_result) > 20:
                Agent._cached_tool_desc = desc_result
                print("[skills] Tool descriptions cached")
        except:
            print("[skills] Dynamic loading skipped (not available on this system)")

    def build_system_prompt(self, user_name=None):
        # Read unique "Soul" (Personality/Role)
        soul_context = ""
        soul_md_path = Path.join(SCRIPT_DIR, "data", "config", "SOUL.md")
        if Path.exists(soul_md_path):
            try:
                with open(soul_md_path, 'r') as f:
                    soul_context = f.read()[:1000]
            except: pass

        # Read User Profile/Context (compact)
        user_context = ""
        user_md_path = Path.join(SCRIPT_DIR, "data", "config", "USER.md")
        if Path.exists(user_md_path):
            try:
                with open(user_md_path, 'r') as f:
                    user_context = f.read()[:500]
            except: pass

        # Read long-term memory
        memory_context = ""
        mem_path = Path.join(SCRIPT_DIR, "data", "memory", "MEMORY.md")
        if Path.exists(mem_path):
            try:
                with open(mem_path, 'r') as f:
                    memory_context = f.read()[:800]
            except: pass

        name_part = ""
        if user_name:
            name_part = "User: " + user_name + "\n"

        # Use cached descriptions if available, otherwise use simple list
        if self._cached_tool_desc:
            tools_section = "Available tools:\n" + self._cached_tool_desc
        else:
            tools_section = "Available tools: " + ", ".join(self.KNOWN_TOOLS)

        prompt = """# MicroBot AI
Personal assistant on OpenWrt. Plain text only, no markdown.
""" + name_part + """
## CRITICAL TOOL RULES
When you need to use a tool, your ENTIRE response must be ONLY the tool call line, nothing else.
Format: TOOL:tool_name:{"arg": "value"}

Examples:
TOOL:get_sys_health:{}
TOOL:web_search:{"query": "weather buenos aires"}
TOOL:save_memory:{"fact": "user likes coffee"}
TOOL:run_command:{"command": "uptime"}

RULES:
1. When using a tool, output ONLY the TOOL: line. Nothing before, nothing after.
2. NEVER make up or guess tool results. You MUST wait for the system to return the real output.
3. After you receive a [Tool Result], use that real data to respond to the user.
4. One tool per message.

""" + tools_section + """

## Memory
Proactively save important user info using save_memory.
""" + ("\n## Personality (SOUL)\n" + soul_context if soul_context else "") + ("\n## User Profile\n" + user_context if user_context else "") + ("\n## Memory\n" + memory_context if memory_context else "")
        return prompt

    def _get_session_file(self, chat_id):
        s_dir = Path.join(SCRIPT_DIR, "data", "sessions")
        if not Path.exists(s_dir):
            try:
                os.makedirs(s_dir)
            except: pass
        return Path.join(s_dir, str(chat_id) + ".json")

    def get_history(self, chat_id):
        if chat_id in self.history:
             return self.history[chat_id]
        
        # Try load from disk
        s_file = self._get_session_file(chat_id)
        if Path.exists(s_file):
            try:
                with open(s_file, 'r') as f:
                    data = json.load(f)
                    self.history[chat_id] = data
                    return data
            except: pass
        return []
        
    def add_to_history(self, chat_id, role, content):
        if chat_id not in self.history:
            self.history[chat_id] = self.get_history(chat_id)
            
        self.history[chat_id].append({"role": role, "content": content})
        # Keep last 10 turns (20 messages)
        while len(self.history[chat_id]) > 20:
            self.history[chat_id].pop(0)
            
        # Save to disk
        s_file = self._get_session_file(chat_id)
        try:
            with open(s_file, 'w') as f:
                json.dump(self.history[chat_id], f)
        except: pass

    def clear_history(self, chat_id):
        self.history[chat_id] = []
        s_file = self._get_session_file(chat_id)
        try:
            os.remove(s_file)
        except: pass

    def execute_tool(self, name, args_json):
        # Parse JSON
        args = {}
        try:
            if isinstance(args_json, dict):
                args = args_json
            else:
                args = json.loads(args_json)
        except:
             # Try a more aggressive cleanup of the JSON string
             # Remove everything after the last }
             try:
                 clean_json = args_json.strip()
                 if "}" in clean_json:
                     clean_json = clean_json[:clean_json.rfind("}")+1]
                 args = json.loads(clean_json)
             except:
                 print("WARNING: Tool args are not valid JSON: " + args_json)
                 return "Error: Invalid JSON arguments"
             
        # Helper: Shell Escape
        def sh_quote(s):
            return "'" + s.replace("'", "'\\''") + "'"
            
        cmd_base = "cd " + SCRIPT_DIR + " && . ./config.sh && . ./tools.sh && "
        
        # Dispatch to specific shell functions with positional args
        if name == "web_search":
            query = args.get("query", "")
            cmd = cmd_base + "tool_web_search " + sh_quote(query)
            
        elif name == "scrape_web":
            url = args.get("url", "")
            cmd = cmd_base + "tool_scrape_web " + sh_quote(url)
            
        elif name == "read_file":
            path = args.get("path", "")
            cmd = cmd_base + "tool_read_file " + sh_quote(path)
            
        elif name == "write_file":
            path = args.get("path", "")
            content = args.get("content", "")
            cmd = cmd_base + "tool_write_file " + sh_quote(path) + " " + sh_quote(content)
            
        elif name == "edit_file":
            path = args.get("path", "")
            old = args.get("old_string", "")
            new = args.get("new_string", "")
            cmd = cmd_base + "tool_edit_file " + sh_quote(path) + " " + sh_quote(old) + " " + sh_quote(new)
            
        elif name == "list_dir":
            prefix = args.get("prefix", "")
            cmd = cmd_base + "tool_list_dir " + sh_quote(prefix)
            
        elif name == "system_info":
            cmd = cmd_base + "tool_system_info"
            
        elif name == "network_status":
            cmd = cmd_base + "tool_network_status"
            
        elif name == "run_command":
            c = args.get("command", "")
            cmd = cmd_base + "tool_run_command " + sh_quote(c)
            
        elif name == "get_current_time":
             cmd = cmd_base + "tool_get_time"
             
        elif name == "get_weather":
             loc = args.get("location", "")
             cmd = cmd_base + "tool_get_weather " + sh_quote(loc)
             
        elif name == "set_schedule":
             cron_expr = args.get("cron", args.get("cron_expression", args.get("schedule", "")))
             content = args.get("content", args.get("message", args.get("command", "")))
             c_id = str(self._current_chat_id) if hasattr(self, '_current_chat_id') else ""
             sched_id = args.get("id", "")
             task_type = args.get("type", "msg")
             cmd = cmd_base + "tool_set_schedule " + sh_quote(cron_expr) + " " + sh_quote(content) + " " + sh_quote(c_id) + " " + sh_quote(sched_id) + " " + sh_quote(task_type)
             
        elif name == "list_schedules":
             cmd = cmd_base + "tool_list_schedules"
             
        elif name == "remove_schedule":
             sched_id = args.get("id", "")
             cmd = cmd_base + "tool_remove_schedule " + sh_quote(sched_id)

        elif name == "set_probe":
             cron_expr = args.get("cron", args.get("cron_expression", ""))
             probe_name = args.get("probe", "")
             c_id = str(self._current_chat_id) if hasattr(self, '_current_chat_id') else ""
             sched_id = args.get("id", "")
             cmd = cmd_base + "tool_set_probe " + sh_quote(cron_expr) + " " + sh_quote(probe_name) + " " + sh_quote(c_id) + " " + sh_quote(sched_id)
             
        elif name == "save_memory":
             fact = args.get("fact", "")
             cmd = cmd_base + "tool_save_memory " + sh_quote(fact)
             
        else:
             # Generic Fallback for Plugins: call tool_{name} with JSON args
             # This allows plugins to define their own shell functions
             cmd = cmd_base + "tool_" + name + " " + sh_quote(json.dumps(args))
            
        # print("DEBUG: Executing Tool Command: " + cmd)
        return run_command(cmd)



    def extract_text(self, resp):
        """Extract text content from LLM response (OpenRouter or Anthropic)."""
        if not resp:
            return ""
        if self.llm.provider == "openrouter":
            choices = resp.get("choices", [])
            if choices:
                return choices[0].get("message", {}).get("content", "")
        else:
            text = ""
            for block in resp.get("content", []):
                if block.get("type") == "text":
                    text += block.get("text", "")
            return text
        return ""

    def detect_tool(self, content):
        """Detect tool call in LLM output. Returns (name, args) or (None, None).
        
        Supports two formats:
          1. TOOL:name:{args}  (preferred)
          2. name {args}       (bare fallback)
        """
        # Method 1: Explicit TOOL: prefix (anywhere in line)
        for line in content.split("\n"):
            line = line.strip()
            idx = line.upper().find("TOOL:")
            if idx != -1:
                payload = line[idx + 5:]
                parts = payload.split(":", 1)
                name = parts[0].strip()
                args = parts[1].strip() if len(parts) > 1 else "{}"
                return name, args
        
        # Method 2: Bare tool call (e.g. "get_sys_health {}" or "web_search({"query":"x"})")
        first_line = content.strip().split("\n")[0].strip()
        for known in self.KNOWN_TOOLS:
            if first_line.startswith(known):
                rest = first_line[len(known):].strip()
                # Strip parentheses wrapper
                if rest.startswith("(") and rest.endswith(")"):
                    rest = rest[1:-1]
                if not rest or rest == "()":
                    return known, "{}"
                if rest.startswith("{"):
                    return known, rest
                return known, "{}"
        
        return None, None

    def process_message(self, chat_id, user_text, user_name=None):
        """ReAct Agent Loop (modeled on MimiClaw's agent_loop.c).
        
        The loop follows the Think -> Act -> Observe cycle:
          1. THINK: Send message history to LLM, get response
          2. ACT:   If response contains a tool call, execute it
          3. OBSERVE: Feed tool result back into history, loop
          4. RESPOND: If no tool call, the response is final text
        """
        def pick(lst):
            """Pick from list without random module (MicroPython safe)."""
            return lst[int(time.time()) % len(lst)]
        
        self._current_chat_id = chat_id
        self.add_to_history(chat_id, "user", user_text)
        
        system_prompt = self.build_system_prompt(user_name)
        messages = self.get_history(chat_id)
        
        max_iterations = 10
        final_text = ""
        
        # --- ReAct Loop ---
        for iteration in range(max_iterations):
            
            # Only send status on tool iterations (iter > 0)
            if iteration > 0:
                phrases = ["Still working on it... \ud83d\udd27", "Just a moment more... \u2699\ufe0f", "Almost there... \ud83d\udcaa"]
                send_telegram_msg(chat_id, pick(phrases), self.token)
            
            # 1. THINK: Call LLM
            print("[react] Iter " + str(iteration + 1) + " | Think...")
            resp = self.llm.chat(messages, system_prompt)
            
            if not resp:
                print("[react] ERROR: Empty LLM response")
                if iteration == 0:
                    return "Error contacting AI. Please try again."
                break
            
            content = self.extract_text(resp)
            if not content:
                print("[react] ERROR: No text in response")
                print("[react] Raw: " + str(resp)[:200])
                if iteration == 0:
                    return "Error: Empty response from AI."
                break
            
            print("[react] Response: " + content[:120] + ("..." if len(content) > 120 else ""))
            
            # 2. ACT: Check for tool call
            t_name, t_args = self.detect_tool(content)
            
            if not t_name:
                # No tool -> this is the final answer
                print("[react] Final answer (no tool detected)")
                final_text = content
                self.add_to_history(chat_id, "assistant", final_text)
                break
            
            # Tool detected -> execute it
            print("[react] Act: " + t_name + " | " + t_args[:80])
            
            # Add assistant's tool-calling message to history
            self.add_to_history(chat_id, "assistant", "TOOL:" + t_name + ":" + t_args)
            
            # Security gate
            if "config.json" in t_args or "microbot.py" in t_args:
                t_result = "Error: Access to system files is forbidden."
            else:
                t_result = self.execute_tool(t_name, t_args)
            
            # 3. OBSERVE: Feed result back
            if len(t_result) > 2000:
                t_result = t_result[:2000] + "... (truncated)"
            
            print("[react] Observe: " + str(len(t_result)) + " bytes from " + t_name)
            
            # Add tool result as user message (the "observation")
            self.add_to_history(chat_id, "user", "[Tool Result: " + t_name + "]\n" + t_result)
            
            # Refresh messages for next iteration
            messages = self.get_history(chat_id)
        
        if not final_text:
            final_text = "I ran into a problem processing your request."
        
        return final_text

def send_telegram_msg(chat_id, text, token):
    """Refactored helper to send Telegram messages via curl (no temp files)"""
    if not text or not token:
        return
        
    # Strip markdown and send as plain text
    clean_text = strip_markdown(text)
    
    # Build JSON inline for curl -d (no temp file)
    # Escape quotes and backslashes for JSON
    json_text = clean_text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    json_body = '{"chat_id":' + str(chat_id) + ',"text":"' + json_text + '"}'
    
    send_url = "https://api.telegram.org/bot" + token + "/sendMessage"
    cmd = "curl -k -s -H 'Content-Type: application/json' -d '" + json_body.replace("'", "'\\''") + "' '" + send_url + "'"
    
    s_res = run_command(cmd)
    
    if not s_res or '"ok":true' not in s_res:
        # Fallback: URL-encoded form post (most compatible)
        # Simple manual encoding for minimal environments
        encoded = clean_text.replace(" ", "%20").replace("\n", "%0A").replace("&", "%26")
        cmd2 = "curl -k -s '" + send_url + "?chat_id=" + str(chat_id) + "&text=" + encoded + "'"
        run_command(cmd2)

def main():
    print("=" * 40)
    print("   MicroBot AI - MicroPython Version")
    print("=" * 40)
    
    # Check curl (required now)
    curl_ver = run_command("curl --version 2>&1 | head -1")
    if not curl_ver:
        # Check if we can run curl anyway (fallback)
        test_curl = run_command("curl --version")
        if not test_curl:
            print("ERROR: curl is required. Please install with 'opkg install curl'")
            sys.exit(1)
        
    config_data = {}
    if Path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                config_data = json.load(f)
        except:
            print("Error loading config.json")
            
    agent = Agent(config_data)

    # Try dynamic skill loading (safe - if it fails, hardcoded tools still work)
    Agent.load_skills()

    token = config_data.get("tg_token")
    
    if not token:
        print("ERROR: tg_token not set in config")
        sys.exit(1)
        
    print("Bot Token: " + (token[:10] if token else "None") + "...")
    print("Starting polling loop...")
    
    offset = 0
    
    while True:
        try:
            # Polling URL
            url = "https://api.telegram.org/bot" + token + "/getUpdates?timeout=30&allowed_updates=%5B%22message%22%5D"
            if offset > 0:
                url += "&offset=" + str(offset)
                
            # Poll with curl
            cmd = "curl -k -s -m 40 \"" + url + "\""
            resp_str = run_command(cmd)
            
            if not resp_str or not resp_str.startswith("{"):
                time.sleep(0.5)
                continue
                
            data = json.loads(resp_str)
            
            if not data.get("ok"):
                # Conflict error check
                if data.get("error_code") == 409:
                     print("Conflict error: Sleeping...")
                     time.sleep(5)
                continue
                
            updates = data.get("result", [])
            for update in updates:
                update_id = update.get("update_id")
                offset = update_id + 1
                
                if "message" not in update:
                    continue
                    
                msg = update["message"]
                chat_id = msg["chat"]["id"]
                text = msg.get("text", "")
                
                if not text:
                    continue
                    
                # DEBUG: Print raw message structure to debug username issue
                # print("DEBUG: MSG: " + json.dumps(msg))
                
                user = msg.get("from", {})
                username = user.get("username", "")
                first_name = user.get("first_name", "")
                
                display_name = username or first_name or "unknown"
                print("\n[telegram] @" + display_name + ": " + text)
                
                # Send typing
                run_command("curl -k -s \"https://api.telegram.org/bot" + token + "/sendChatAction?chat_id=" + str(chat_id) + "&action=typing\"")
                
                response = ""
                # Commands
                if text == "/start":
                    response = "Hello! I'm MicroBot AI (Python). How can I help?"
                    agent.clear_history(chat_id)
                elif text == "/clear":
                    agent.clear_history(chat_id)
                    response = "Memory cleared."
                else:
                    # Process with Agent
                    response = agent.process_message(chat_id, text, display_name)
                    
                # Send final response
                send_telegram_msg(chat_id, response, token)

        except KeyboardInterrupt:
            print("\nStopping...")
            break
        except Exception as e:
            print("Loop Error: " + str(e))
            # sys.print_exception(e)
            time.sleep(1)

if __name__ == "__main__":
    main()
