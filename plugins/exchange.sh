#!/bin/sh
# MicroBot Plugin: Exchange Rate
# Provides: tool_get_exchange_rate

tool_get_exchange_rate() {
    # Arguments are passed as a single JSON string if called via generic fallback
    local args="$1"
    local base="USD"
    local target="ARS"
    
    # Try to extract base/target from JSON if possible, else use defaults
    if [ -n "$args" ]; then
        if command -v jsonfilter >/dev/null 2>&1; then
            local b=$(echo "$args" | jsonfilter -e '@.base' 2>/dev/null)
            [ -n "$b" ] && base="$b"
            local t=$(echo "$args" | jsonfilter -e '@.target' 2>/dev/null)
            [ -n "$t" ] && target="$t"
        else
            # Manual fallback for args
            local b=$(echo "$args" | grep -o '"base"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"base"[[:space:]]*:[[:space:]]*"//;s/"//')
            [ -n "$b" ] && base="$b"
            local t=$(echo "$args" | grep -o '"target"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"target"[[:space:]]*:[[:space:]]*"//;s/"//')
            [ -n "$t" ] && target="$t"
        fi
    fi

    echo "Fetching exchange rate for ${base}/${target}..."
    
    local url="https://open.er-api.com/v6/latest/${base}"
    local result
    if command -v curl >/dev/null 2>&1; then
        result=$(curl -k -s -m 10 "$url")
    else
        result=$(wget -q -O - --no-check-certificate "$url" 2>/dev/null)
    fi
    
    if [ -n "$result" ]; then
        local rate=""
        if command -v jsonfilter >/dev/null 2>&1; then
            rate=$(echo "$result" | jsonfilter -e "@.rates.${target}" 2>/dev/null)
        fi
        
        # Robust fallback for rate extraction
        if [ -z "$rate" ]; then
            # Look for "TARGET": VALUE
            rate=$(echo "$result" | grep -o "\"${target}\"[[:space:]]*:[[:space:]]*[0-9.]*" | sed "s/.*:[[:space:]]*//")
        fi

        if [ -n "$rate" ]; then
            echo "1 ${base} = ${rate} ${target}"
            echo "Data provider: https://www.exchangerate-api.com"
        else
            echo "Error: Target currency ${target} not found for base ${base}."
        fi
    else
        echo "Error: Could not fetch data from API."
    fi
}
