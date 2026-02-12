#!/bin/sh
# MicroBot AI - Tools
# Do not source config.sh here - it's sourced by main script

# Tool: Get current time
tool_get_time() {
    local result
    if command -v curl >/dev/null 2>&1; then
        result=$(curl -k -s "http://worldtimeapi.org/api/ip")
    else
        result=$(wget -q -O - --no-check-certificate "http://worldtimeapi.org/api/ip" 2>/dev/null)
    fi
    
    if [ -n "$result" ]; then
        local datetime=$(echo "$result" | jsonfilter -e '@.datetime')
        local tz=$(echo "$result" | jsonfilter -e '@.timezone')
        echo "Current time: ${datetime} (timezone: ${tz})"
    else
        date "+Current time: %Y-%m-%d %H:%M:%S (local)"
    fi
}

# Helper: JSON Escape
json_escape() {
    # Simple escape for JSON strings
    # 1. Backslashes (double escape to be safe in sed replacement)
    # 2. Quotes
    # 3. Tabs
    # 4. Newlines -> space (simplified)
    # Note: awk might be missing on minimal systems, use printf + sed
    local tab=$(printf '\t')
    printf '%s' "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed "s/$tab/\\\\t/g" | tr '\n' ' ' | sed 's/  */ /g'
}

# Tool: Web search
# Uses Brave Search API if key available, else scrapes DuckDuckGo HTML
tool_web_search() {
    local query="$1"
    
    if [ -z "$query" ]; then
        echo "Error: Search query required"
        return
    fi
    
    # URL-encode the query (simple: spaces + basic chars)
    local encoded_q=$(echo "$query" | sed 's/ /+/g; s/&/%26/g; s/?/%3F/g; s/#/%23/g')
    
    # ------- Try Brave API first -------
    if [ -n "$SEARCH_KEY" ] && [ "$SEARCH_KEY" != "YOUR_API_KEY" ]; then
        local api_url="https://api.search.brave.com/res/v1/web/search?q=${encoded_q}&count=5"
        local result
        result=$(curl -k -s -m 10 \
            -H "Accept: application/json" \
            -H "X-Subscription-Token: ${SEARCH_KEY}" \
            "$api_url")
        
        if [ -n "$result" ]; then
            local count=$(echo "$result" | jsonfilter -e '@.web.results[*]' 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ] 2>/dev/null; then
                local i=0
                while [ $i -lt $count ] && [ $i -lt 5 ]; do
                    local title=$(echo "$result" | jsonfilter -e "@.web.results[$i].title" 2>/dev/null)
                    local link=$(echo "$result" | jsonfilter -e "@.web.results[$i].url" 2>/dev/null)
                    local desc=$(echo "$result" | jsonfilter -e "@.web.results[$i].description" 2>/dev/null | head -c 200)
                    echo "$title"
                    echo "$link"
                    echo "$desc"
                    echo ""
                    i=$((i + 1))
                done
                return
            fi
        fi
    fi
    # ------- Fallback: Scrape DuckDuckGo HTML (zero storage - all piped) -------
    local ddg_url="https://html.duckduckgo.com/html/?q=${encoded_q}"
    local ua="Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"
    
    echo "=== Search Results for: $query ==="
    echo ""
    
    # Single curl | awk pipeline: extract links and text in one pass
    curl -k -s -L -A "$ua" -m 15 "$ddg_url" 2>/dev/null | awk '
    BEGIN { lc=0; tc=0 }
    {
        # Extract uddg= links
        line = $0
        while (match(line, /href="[^"]*uddg=[^"]*"/)) {
            href = substr(line, RSTART+6, RLENGTH-7)
            line = substr(line, RSTART+RLENGTH)
            # Extract uddg= value
            if (match(href, /uddg=[^&]*/)) {
                url = substr(href, RSTART+5, RLENGTH-5)
                # Basic URL decode
                gsub(/%3A/, ":", url); gsub(/%2F/, "/", url)
                gsub(/%3F/, "?", url); gsub(/%3D/, "=", url)
                gsub(/%26/, "\\&", url); gsub(/%2C/, ",", url)
                gsub(/%20/, " ", url); gsub(/%25/, "%", url)
                if (lc < 8) { links[lc++] = url }
            }
        }
        # Accumulate text (strip tags)
        gsub(/<[^>]*>/, " ")
        gsub(/[ \t]+/, " ")
        if (length($0) > 1 && tc < 3000) {
            tc += length($0)
            text = text $0 " "
        }
    }
    END {
        print "--- Top Links ---"
        for (i=0; i<lc; i++) print links[i]
        print ""
        print "--- Content Preview ---"
        print substr(text, 1, 3000)
    }'
}

# Tool: Scrape web (zero storage - direct curl | awk pipeline)
# Enhanced: extracts title, meta description, headings, and body text
tool_scrape_web() {
    local url="$1"
    
    if [ -z "$url" ]; then
        echo "Error: URL required"
        return
    fi
    
    local ua="Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"
    
    # Single curl | awk pipeline: structured extraction in one streaming pass
    curl -k -s -L -A "$ua" -m 15 "$url" 2>/dev/null | awk '
    BEGIN { skip=0; tc=0; lc=0; hc=0; title=""; meta="" }
    {
        # Extract page title
        if (title == "" && match($0, /<title[^>]*>[^<]*/)) {
            t = substr($0, RSTART, RLENGTH)
            gsub(/<title[^>]*>/, "", t)
            gsub(/^ +| +$/, "", t)
            if (length(t) > 0) title = t
        }

        # Extract meta description
        if (meta == "" && match($0, /name="description"[^>]*content="[^"]*/)) {
            m = substr($0, RSTART, RLENGTH)
            if (match(m, /content="[^"]*/)) {
                meta = substr(m, RSTART+9, RLENGTH-9)
            }
        }

        # Extract headings (h1-h3)
        line2 = $0
        while (match(line2, /<h[1-3][^>]*>[^<]*/)) {
            h = substr(line2, RSTART, RLENGTH)
            line2 = substr(line2, RSTART+RLENGTH)
            gsub(/<h[1-3][^>]*>/, "", h)
            gsub(/^ +| +$/, "", h)
            if (length(h) > 1 && hc < 15) { headings[hc++] = h }
        }

        # Extract http links from href attributes
        line = $0
        while (match(line, /href="http[^"]*"/)) {
            href = substr(line, RSTART+6, RLENGTH-7)
            line = substr(line, RSTART+RLENGTH)
            if (lc < 15) { links[lc++] = href }
        }
        
        # Track script/style/nav/footer blocks
        if (match($0, /<script/)) skip=1
        if (match($0, /<\/script>/)) { skip=0; next }
        if (match($0, /<style/)) skip=1
        if (match($0, /<\/style>/)) { skip=0; next }
        if (match($0, /<nav[ >]/)) skip=1
        if (match($0, /<\/nav>/)) { skip=0; next }
        if (match($0, /<footer[ >]/)) skip=1
        if (match($0, /<\/footer>/)) { skip=0; next }
        if (skip) next
        
        # Strip HTML tags and accumulate text
        gsub(/<[^>]*>/, " ")
        gsub(/&nbsp;/, " ")
        gsub(/&amp;/, "\\&")
        gsub(/&lt;/, "<")
        gsub(/&gt;/, ">")
        gsub(/[ \t]+/, " ")
        gsub(/^ +| +$/, "")
        if (length($0) > 2 && tc < 6000) {
            tc += length($0)
            text = text $0 " "
        }
    }
    END {
        if (tc == 0) { print "Error: Empty or unreachable page"; exit }
        if (title != "") print "Title: " title
        if (meta != "") print "Description: " meta
        print ""
        if (hc > 0) {
            print "=== Headings ==="
            for (i=0; i<hc; i++) print "  " headings[i]
            print ""
        }
        print "=== Content ==="
        print substr(text, 1, 6000)
        print ""
        print "=== Links ==="
        for (i=0; i<lc; i++) print links[i]
    }'
}

# Tool: Read file
tool_read_file() {
    local path="$1"
    
    # Check if path starts with DATA_DIR
    case "$path" in
        "${DATA_DIR}"*) ;;
        *)
            echo "Error: Path must start with ${DATA_DIR}"
            return
            ;;
    esac
    
    if [ ! -f "$path" ]; then
        echo "Error: File not found: $path"
        return
    fi
    
    cat "$path"
}

# Tool: Write file
tool_write_file() {
    local path="$1"
    local content="$2"
    
    case "$path" in
        "${DATA_DIR}"*) ;;
        *)
            echo "Error: Path must start with ${DATA_DIR}"
            return
            ;;
    esac
    
    mkdir -p "$(dirname "$path")"
    echo "$content" > "$path"
    echo "File written successfully: $path"
}

# Tool: Edit file (find and replace)
tool_edit_file() {
    local path="$1"
    local old_str="$2"
    local new_str="$3"
    
    case "$path" in
        "${DATA_DIR}"*) ;;
        *)
            echo "Error: Path must start with ${DATA_DIR}"
            return
            ;;
    esac
    
    if [ ! -f "$path" ]; then
        echo "Error: File not found: $path"
        return
    fi
    
    sed -i "s/${old_str}/${new_str}/" "$path"
    echo "File edited successfully: $path"
}

# Tool: List directory
tool_list_dir() {
    local prefix="${1:-${DATA_DIR}}"
    
    case "$prefix" in
        "${DATA_DIR}"*) ;;
        *)
            prefix="${DATA_DIR}"
            ;;
    esac
    
    find "$prefix" -type f 2>/dev/null | head -50
}

# Tool: System info (OpenWrt specific)
tool_system_info() {
    local hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null)
    local uptime_raw=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' | cut -d. -f1)
    [ -z "$uptime_raw" ] && uptime_raw=0
    
    local uptime_days=$((uptime_raw / 86400))
    local uptime_hours=$((uptime_raw % 86400 / 3600))
    local uptime_mins=$((uptime_raw % 3600 / 60))
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}')
    
    local mem_total=$(free 2>/dev/null | grep Mem | awk '{print $2}')
    local mem_used=$(free 2>/dev/null | grep Mem | awk '{print $3}')
    local mem_free=$(free 2>/dev/null | grep Mem | awk '{print $4}')
    
    local cpu_temp=""
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        if [ -n "$temp_raw" ] && [ "$temp_raw" -eq "$temp_raw" ] 2>/dev/null; then
            cpu_temp=$((temp_raw / 1000))
            cpu_temp="${cpu_temp}C"
        fi
    fi
    
    local disk_total=$(df / 2>/dev/null | tail -1 | awk '{print $2}')
    local disk_used=$(df / 2>/dev/null | tail -1 | awk '{print $3}')
    local disk_free=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
    
    local openwrt_ver=""
    if [ -f /etc/openwrt_release ]; then
        openwrt_ver=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
    fi
    
    echo "=== System Info ==="
    echo "Hostname: $hostname"
    [ -n "$openwrt_ver" ] && echo "OpenWrt: $openwrt_ver"
    echo "Uptime: ${uptime_days}d ${uptime_hours}h ${uptime_mins}m"
    echo "Load: $load"
    echo "Memory: ${mem_used}/${mem_total} KB used (${mem_free} KB free)"
    [ -n "$cpu_temp" ] && echo "CPU Temp: $cpu_temp"
    echo "Disk: ${disk_used}/${disk_total} KB used (${disk_free} KB free)"
}

# Tool: Network status
tool_network_status() {
    local wan_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    local wan_iface=$(ip route 2>/dev/null | grep default | awk '{print $5}')
    
    echo "=== Network Status ==="
    echo "WAN IP: $wan_ip"
    echo "WAN Interface: $wan_iface"
    
    echo ""
    echo "=== WiFi Interfaces ==="
    if command -v iw >/dev/null 2>&1; then
        iw dev 2>/dev/null | grep -E "Interface|ssid|type" | head -10
    else
        echo "iw not available"
    fi
    
    echo ""
    echo "=== Connected Devices (ARP) ==="
    ip neigh show 2>/dev/null | grep -v FAILED | head -10
}

# Tool: Run shell command
tool_run_command() {
    local cmd="$1"
    
    # Blocked commands and sensitive files for safety
    case "$cmd" in
        *"rm -rf /"*|*"mkfs"*|*"dd if="*|*"chmod 777 /"*|*" > /etc/passwd"*|*" > /etc/shadow"*|*"config.json"*|*"tg_token"*|*"openrouter_key"*|*"api_key"*)
            echo "Error: Command blocked for safety. Access to configuration or sensitive keys is forbidden."
            return
            ;;
    esac
    
    # Run command with timeout
    local result=$(timeout 10 sh -c "$cmd" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo "Error: Command timed out (10s limit)"
    else
        echo "$result"
    fi
}

# Tool: Restart service
tool_restart_service() {
    local service="$1"
    
    # Only allow specific services
    local allowed="firewall network dnsmasq uhttpd dropbear microbot-ai odhcpd log"
    
    if ! echo "$allowed" | grep -qw "$service"; then
        echo "Error: Can only restart: $allowed"
        return
    fi
    
    if /etc/init.d/"$service" restart 2>&1; then
        echo "Service $service restarted successfully"
    else
        echo "Error restarting $service"
    fi
}

# Tool: List services
tool_list_services() {
    echo "=== Running Services ==="
    for s in /etc/init.d/*; do
        if [ -x "$s" ]; then
            local name=$(basename "$s")
            if "$s" enabled 2>/dev/null; then
                echo "$name: enabled"
            fi
        fi
    done | head -20
}

# Tool: Get weather using Open-Meteo API (free, no API key needed)
tool_get_weather() {
    local location="$1"
    
    if [ -z "$location" ]; then
        echo "Error: Location required (e.g. 'Buenos Aires' or 'City, Province')"
        return
    fi
    
    local encoded_loc=$(echo "$location" | sed 's/ /+/g; s/,/%2C/g')
    
    # Step 1: Geocode city name to coordinates
    local geo_resp
    geo_resp=$(curl -k -s -m 10 "https://geocoding-api.open-meteo.com/v1/search?name=${encoded_loc}&count=1&language=en" 2>/dev/null)
    
    if [ -z "$geo_resp" ]; then
        echo "Error: Could not geocode location '$location'"
        return
    fi
    
    local lat="" lon="" city="" country=""
    if command -v jsonfilter >/dev/null 2>&1; then
        lat=$(echo "$geo_resp" | jsonfilter -e '@.results[0].latitude' 2>/dev/null)
        lon=$(echo "$geo_resp" | jsonfilter -e '@.results[0].longitude' 2>/dev/null)
        city=$(echo "$geo_resp" | jsonfilter -e '@.results[0].name' 2>/dev/null)
        country=$(echo "$geo_resp" | jsonfilter -e '@.results[0].country' 2>/dev/null)
    else
        lat=$(echo "$geo_resp" | grep -o '"latitude":[0-9.-]*' | head -1 | sed 's/"latitude"://')
        lon=$(echo "$geo_resp" | grep -o '"longitude":[0-9.-]*' | head -1 | sed 's/"longitude"://')
        city=$(echo "$geo_resp" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"$//')
        country=$(echo "$geo_resp" | grep -o '"country":"[^"]*"' | head -1 | sed 's/"country":"//;s/"$//')
    fi
    
    if [ -z "$lat" ] || [ -z "$lon" ]; then
        echo "Error: Location '$location' not found"
        return
    fi
    
    # Step 2: Fetch weather from Open-Meteo
    local weather_resp
    weather_resp=$(curl -k -s -m 10 "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max&timezone=auto&forecast_days=3" 2>/dev/null)
    
    if [ -z "$weather_resp" ]; then
        echo "Error: Could not fetch weather data"
        return
    fi
    
    # Parse current weather
    local temp="" feels="" humidity="" wind_speed="" wind_dir="" wcode=""
    if command -v jsonfilter >/dev/null 2>&1; then
        temp=$(echo "$weather_resp" | jsonfilter -e '@.current.temperature_2m' 2>/dev/null)
        feels=$(echo "$weather_resp" | jsonfilter -e '@.current.apparent_temperature' 2>/dev/null)
        humidity=$(echo "$weather_resp" | jsonfilter -e '@.current.relative_humidity_2m' 2>/dev/null)
        wind_speed=$(echo "$weather_resp" | jsonfilter -e '@.current.wind_speed_10m' 2>/dev/null)
        wind_dir=$(echo "$weather_resp" | jsonfilter -e '@.current.wind_direction_10m' 2>/dev/null)
        wcode=$(echo "$weather_resp" | jsonfilter -e '@.current.weather_code' 2>/dev/null)
    else
        temp=$(echo "$weather_resp" | grep -o '"temperature_2m":[0-9.-]*' | head -1 | sed 's/"temperature_2m"://')
        humidity=$(echo "$weather_resp" | grep -o '"relative_humidity_2m":[0-9.-]*' | head -1 | sed 's/"relative_humidity_2m"://')
        wind_speed=$(echo "$weather_resp" | grep -o '"wind_speed_10m":[0-9.-]*' | head -1 | sed 's/"wind_speed_10m"://')
        wcode=$(echo "$weather_resp" | grep -o '"weather_code":[0-9]*' | head -1 | sed 's/"weather_code"://')
    fi
    
    # Translate WMO weather code to description
    local desc="Unknown"
    case "$wcode" in
        0) desc="Clear sky" ;;
        1) desc="Mainly clear" ;;
        2) desc="Partly cloudy" ;;
        3) desc="Overcast" ;;
        45|48) desc="Foggy" ;;
        51|53|55) desc="Drizzle" ;;
        56|57) desc="Freezing drizzle" ;;
        61|63|65) desc="Rain" ;;
        66|67) desc="Freezing rain" ;;
        71|73|75) desc="Snow" ;;
        77) desc="Snow grains" ;;
        80|81|82) desc="Rain showers" ;;
        85|86) desc="Snow showers" ;;
        95) desc="Thunderstorm" ;;
        96|99) desc="Thunderstorm with hail" ;;
    esac
    
    echo "Weather for ${city:-$location}, ${country:-}"
    echo "Condition: $desc"
    echo "Temperature: ${temp}C (feels like ${feels:-$temp}C)"
    echo "Humidity: ${humidity}%"
    echo "Wind: ${wind_speed} km/h"
    
    # Parse 3-day forecast
    local d0_max="" d0_min="" d1_max="" d1_min="" d2_max="" d2_min=""
    if command -v jsonfilter >/dev/null 2>&1; then
        d0_max=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_max[0]' 2>/dev/null)
        d0_min=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_min[0]' 2>/dev/null)
        d1_max=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_max[1]' 2>/dev/null)
        d1_min=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_min[1]' 2>/dev/null)
        d2_max=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_max[2]' 2>/dev/null)
        d2_min=$(echo "$weather_resp" | jsonfilter -e '@.daily.temperature_2m_min[2]' 2>/dev/null)
    fi
    
    if [ -n "$d0_max" ]; then
        echo ""
        echo "Forecast:"
        echo "  Today: ${d0_min}C - ${d0_max}C"
        [ -n "$d1_max" ] && echo "  Tomorrow: ${d1_min}C - ${d1_max}C"
        [ -n "$d2_max" ] && echo "  Day after: ${d2_min}C - ${d2_max}C"
    fi
}

# Tool: HTTP request
tool_http_request() {
    local url="$1"
    local method="${2:-GET}"
    local body="$3"
    
    if [ -z "$url" ]; then
        echo "Error: URL required"
        return
    fi
    
    local result
    if command -v curl >/dev/null 2>&1; then
        if [ "$method" = "POST" ] && [ -n "$body" ]; then
            result=$(curl -k -s -d "$body" "$url")
        else
            result=$(curl -k -s "$url")
        fi
    else
        if [ "$method" = "POST" ] && [ -n "$body" ]; then
            result=$(wget -q -O - --no-check-certificate --post-data="$body" "$url" 2>/dev/null)
        else
            result=$(wget -q -O - --no-check-certificate "$url" 2>/dev/null)
        fi
    fi
    
    echo "$result"
}

# ============================================
# SCHEDULING TOOLS (Native Cron)
# ============================================

# Tool: Set a scheduled task
# Args: $1=cron_expression, $2=message/command/url, $3=chat_id, $4=schedule_id, $5=type (msg|cmd|url|once_msg|once_cmd)
tool_set_schedule() {
    local cron_expr="$1"
    local content="$2"
    local chat_id="$3"
    local sched_id="$4"
    local task_type="${5:-msg}"
    
    if [ -z "$cron_expr" ] || [ -z "$content" ] || [ -z "$chat_id" ]; then
        echo "Error: Required: cron_expression, content, chat_id"
        return
    fi
    
    # Generate ID if not provided
    if [ -z "$sched_id" ]; then
        sched_id="mb_$(date +%s)"
    fi
    
    # Ensure crond is running
    if ! pidof crond >/dev/null 2>&1; then
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
        if ! pidof crond >/dev/null 2>&1; then
            echo "Error: Could not start cron daemon"
            return
        fi
    fi
    
    # Determine script path
    local script_dir
    if [ -n "$SCRIPT_DIR" ]; then
        script_dir="$SCRIPT_DIR"
    else
        script_dir="$(cd "$(dirname "$0")" && pwd)"
    fi
    
    # Clean content for shell safety
    local safe_content=$(echo "$content" | sed "s/'//g")
    
    # Build cron line based on task type
    local cron_line
    case "$task_type" in
        once_msg|once_cmd)
            # One-time tasks pass their own ID so they can self-remove
            cron_line="${cron_expr} ${script_dir}/cron_task.sh ${chat_id} ${task_type} ${sched_id} ${safe_content} #MICROBOT_ID=${sched_id}"
            ;;
        *)
            cron_line="${cron_expr} ${script_dir}/cron_task.sh ${chat_id} ${task_type} ${safe_content} #MICROBOT_ID=${sched_id}"
            ;;
    esac
    
    # Add to crontab (BusyBox requires FILE, use /tmp ramdisk)
    local ct="/tmp/.mb_cron_$$"
    crontab -l > "$ct" 2>/dev/null || true
    
    # Remove old entry if exists
    if grep -q "#MICROBOT_ID=${sched_id}" "$ct" 2>/dev/null; then
        grep -v "#MICROBOT_ID=${sched_id}" "$ct" > "${ct}.n" && mv "${ct}.n" "$ct"
    fi
    
    echo "$cron_line" >> "$ct"
    crontab "$ct"
    local rc=$?
    rm -f "$ct" "${ct}.n"
    
    if [ $rc -eq 0 ]; then
        echo "Schedule set!"
        echo "ID: ${sched_id}"
        echo "Type: ${task_type}"
        echo "Cron: ${cron_expr}"
        echo "Content: ${content}"
        echo "Chat: ${chat_id}"
    else
        echo "Error: Failed to write crontab"
    fi
}

# Tool: List all MicroBot schedules (pure pipe, no temp files)
tool_list_schedules() {
    local cron_data
    cron_data=$(crontab -l 2>/dev/null)
    
    if [ -z "$cron_data" ]; then
        echo "No schedules found (crontab is empty)"
        return
    fi
    
    local found=0
    echo "=== MicroBot Scheduled Tasks ==="
    
    echo "$cron_data" | while IFS= read -r line; do
        case "$line" in
            *"#MICROBOT_ID="*)
                found=1
                local id=$(echo "$line" | grep -o '#MICROBOT_ID=[^ ]*' | sed 's/#MICROBOT_ID=//')
                local cexpr=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
                local msg=$(echo "$line" | sed "s/.*cron_notify.sh [0-9]* //;s/ #MICROBOT_ID=.*//")
                echo ""
                echo "ID: $id"
                echo "  Cron: $cexpr"
                echo "  Message: $msg"
                ;;
        esac
    done
    
    # Check if any were found (subshell workaround)
    if ! echo "$cron_data" | grep -q "#MICROBOT_ID="; then
        echo "No MicroBot schedules found"
    fi
}

# Tool: Remove a schedule by ID
tool_remove_schedule() {
    local sched_id="$1"
    
    if [ -z "$sched_id" ]; then
        echo "Error: Schedule ID required"
        return
    fi
    
    # Check if ID exists
    if ! crontab -l 2>/dev/null | grep -q "#MICROBOT_ID=${sched_id}"; then
        echo "Error: Schedule ID '${sched_id}' not found"
        echo "Use list_schedules to see available IDs"
        return
    fi
    
    # Use /tmp ramdisk for the required temp file
    local ct="/tmp/.mb_cron_$$"
    crontab -l 2>/dev/null | grep -v "#MICROBOT_ID=${sched_id}" > "$ct"
    
    if [ ! -s "$ct" ]; then
        crontab -r 2>/dev/null
    else
        crontab "$ct"
    fi
    
    rm -f "$ct"
    echo "Schedule '${sched_id}' removed successfully"
}

# Tool: Set a proactive monitoring probe
# Args: $1=cron_expression, $2=probe_name, $3=chat_id, $4=schedule_id
# Probe names: disk_check, mem_check, net_check, load_check, service_check, custom
tool_set_probe() {
    local cron_expr="$1"
    local probe_name="$2"
    local chat_id="$3"
    local sched_id="${4:-probe_$(date +%s)}"

    if [ -z "$cron_expr" ] || [ -z "$probe_name" ] || [ -z "$chat_id" ]; then
        echo "Error: Required: cron_expression, probe_name, chat_id"
        echo "Available probes: disk_check, mem_check, net_check, load_check, service_check, custom"
        return
    fi

    # Validate probe name
    case "$probe_name" in
        disk_check|mem_check|net_check|load_check|service_check|custom) ;;
        *)
            echo "Error: Unknown probe '$probe_name'"
            echo "Available: disk_check, mem_check, net_check, load_check, service_check, custom"
            return
            ;;
    esac

    # Ensure crond is running
    if ! pidof crond >/dev/null 2>&1; then
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
    fi

    local script_dir
    if [ -n "$SCRIPT_DIR" ]; then
        script_dir="$SCRIPT_DIR"
    else
        script_dir="$(cd "$(dirname "$0")" && pwd)"
    fi

    local cron_line="${cron_expr} ${script_dir}/cron_probe.sh ${chat_id} ${probe_name} #MICROBOT_ID=${sched_id}"

    # Add to crontab
    local ct="/tmp/.mb_cron_$$"
    crontab -l > "$ct" 2>/dev/null || true

    # Remove old entry if exists
    if grep -q "#MICROBOT_ID=${sched_id}" "$ct" 2>/dev/null; then
        grep -v "#MICROBOT_ID=${sched_id}" "$ct" > "${ct}.n" && mv "${ct}.n" "$ct"
    fi

    echo "$cron_line" >> "$ct"
    crontab "$ct"
    local rc=$?
    rm -f "$ct" "${ct}.n"

    if [ $rc -eq 0 ]; then
        echo "Proactive probe set!"
        echo "ID: ${sched_id}"
        echo "Probe: ${probe_name}"
        echo "Cron: ${cron_expr}"
        echo "I will monitor silently and only alert you if something needs attention."
    else
        echo "Error: Failed to write crontab"
    fi
}

# Execute tool by name
tool_execute() {
    local name="$1"
    local args="$2"
    
    case "$name" in
        "get_current_time")
            tool_get_time
            ;;
        "web_search")
            local query=$(echo "$args" | jsonfilter -e '@.query')
            tool_web_search "$query"
            ;;
        "scrape_web")
            local url=$(echo "$args" | jsonfilter -e '@.url')
            tool_scrape_web "$url"
            ;;
        "read_file")
            local path=$(echo "$args" | jsonfilter -e '@.path')
            tool_read_file "$path"
            ;;
        "write_file")
            local path=$(echo "$args" | jsonfilter -e '@.path')
            local content=$(echo "$args" | jsonfilter -e '@.content')
            tool_write_file "$path" "$content"
            ;;
        "edit_file")
            local path=$(echo "$args" | jsonfilter -e '@.path')
            local old_str=$(echo "$args" | jsonfilter -e '@.old_string')
            local new_str=$(echo "$args" | jsonfilter -e '@.new_string')
            tool_edit_file "$path" "$old_str" "$new_str"
            ;;
        "list_dir")
            local prefix=$(echo "$args" | jsonfilter -e '@.prefix')
            tool_list_dir "$prefix"
            ;;
        "system_info")
            tool_system_info
            ;;
        "network_status")
            tool_network_status
            ;;
        "run_command")
            local cmd=$(echo "$args" | jsonfilter -e '@.command')
            tool_run_command "$cmd"
            ;;
        "restart_service")
            local service=$(echo "$args" | jsonfilter -e '@.service')
            tool_restart_service "$service"
            ;;
        "list_services")
            tool_list_services
            ;;
        "get_weather")
            local location=$(echo "$args" | jsonfilter -e '@.location' 2>/dev/null)
            tool_get_weather "$location"
            ;;
        "http_request")
            local url=$(echo "$args" | jsonfilter -e '@.url')
            local method=$(echo "$args" | jsonfilter -e '@.method')
            local body=$(echo "$args" | jsonfilter -e '@.body')
            tool_http_request "$url" "$method" "$body"
            ;;
        "set_schedule")
            local cron_expr=$(echo "$args" | jsonfilter -e '@.cron' 2>/dev/null)
            local content=$(echo "$args" | jsonfilter -e '@.content' 2>/dev/null)
            # Fallback: also accept "message" field
            [ -z "$content" ] && content=$(echo "$args" | jsonfilter -e '@.message' 2>/dev/null)
            local chat_id=$(echo "$args" | jsonfilter -e '@.chat_id' 2>/dev/null)
            local sched_id=$(echo "$args" | jsonfilter -e '@.id' 2>/dev/null)
            local task_type=$(echo "$args" | jsonfilter -e '@.type' 2>/dev/null)
            [ -z "$task_type" ] && task_type="msg"
            tool_set_schedule "$cron_expr" "$content" "$chat_id" "$sched_id" "$task_type"
            ;;
        "list_schedules")
            tool_list_schedules
            ;;
        "remove_schedule")
            local sched_id=$(echo "$args" | jsonfilter -e '@.id' 2>/dev/null)
            tool_remove_schedule "$sched_id"
            ;;
        *)
            echo "Error: Unknown tool: $name"
            ;;
    esac
}

# Get tools JSON for API
get_tools_json() {
    echo '[{"name":"get_current_time","description":"Get current date and time","input_schema":{"type":"object","properties":{}}},{"name":"web_search","description":"Search the web for current information","input_schema":{"type":"object","properties":{"query":{"type":"string","description":"Search query"}},"required":["query"]}},{"name":"scrape_web","description":"Fetch user-readable text from a URL (web crawler)","input_schema":{"type":"object","properties":{"url":{"type":"string","description":"URL to fetch"}},"required":["url"]}},{"name":"read_file","description":"Read file from /data/","input_schema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},{"name":"write_file","description":"Write file to /data/","input_schema":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}},{"name":"edit_file","description":"Edit file with find/replace","input_schema":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"}},"required":["path","old_string","new_string"]}},{"name":"list_dir","description":"List files in /data/","input_schema":{"type":"object","properties":{"prefix":{"type":"string"}}}},{"name":"system_info","description":"Get system info: hostname, uptime, CPU, memory, disk","input_schema":{"type":"object","properties":{}}},{"name":"network_status","description":"Get network status: WAN IP, WiFi, connected devices","input_schema":{"type":"object","properties":{}}},{"name":"run_command","description":"Execute a shell command (with safety restrictions)","input_schema":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}},{"name":"list_services","description":"List running OpenWrt services","input_schema":{"type":"object","properties":{}}},{"name":"restart_service","description":"Restart an OpenWrt service","input_schema":{"type":"object","properties":{"service":{"type":"string"}},"required":["service"]}},{"name":"get_weather","description":"Get current weather","input_schema":{"type":"object","properties":{"location":{"type":"string"}}}},{"name":"http_request","description":"Make an HTTP request","input_schema":{"type":"object","properties":{"url":{"type":"string"},"method":{"type":"string"},"body":{"type":"string"}},"required":["url"]}}]'
}
# Tool: Save a fact to long-term memory
tool_save_memory() {
    local fact="$1"
    if [ -z "$fact" ]; then
        echo "Error: Content required"
        return
    fi
    
    local mem_file="${SCRIPT_DIR}/data/memory/MEMORY.md"
    local date_str=$(date "+%Y-%m-%d %H:%M")
    
    # Ensure directory exists
    mkdir -p "$(dirname "$mem_file")"
    
    echo "- [${date_str}] ${fact}" >> "$mem_file"
    echo "Memory saved: ${fact}"
}

# Helper: List all available tools (including plugins)
tool_list_all_tools() {
    echo "--- Standard Tools ---"
    echo "web_search, get_current_time, read_file, write_file, edit_file, list_dir, system_info, network_status, run_command, list_services, restart_service, get_weather, http_request, set_schedule, list_schedules, remove_schedule, save_memory"
    
    if [ -d "${SCRIPT_DIR}/plugins" ]; then
        echo "--- Plugin Tools ---"
        grep -h "^tool_.*()" "${SCRIPT_DIR}/plugins"/*.sh 2>/dev/null | sed 's/().*//;s/tool_//' | tr '\n' ',' | sed 's/,$//'
        echo ""
    fi
}

# Load Plugins from ./plugins/*.sh
PLUGIN_DIR="${SCRIPT_DIR:-.}/plugins"
if [ -d "$PLUGIN_DIR" ]; then
    for plugin in "$PLUGIN_DIR"/*.sh; do
        if [ -f "$plugin" ]; then
            . "$plugin"
        fi
    done
fi
