#!/bin/bash
# Syncthing Event Listener for Janus
# Push-based file sync monitoring
# Replaces polling with real-time events

API_KEY="RVh5h7Y2oVWvEMhHghVP7CYuTSroriMa"
SYNCTHING_URL="http://127.0.0.1:8384"
WATCH_FOLDER="agent-reports"
LOG_FILE="/tmp/janus-syncthing-events.log"
LAST_EVENT_ID=0

echo "[$(date)] Syncthing Event Listener started (Janus)" >> "$LOG_FILE"

while true; do
    # Long-poll for events
    response=$(curl -s -H "X-API-Key: $API_KEY" \
        "${SYNCTHING_URL}/rest/events?since=${LAST_EVENT_ID}&limit=100" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "[$(date)] ERROR: Failed to connect to Syncthing API" >> "$LOG_FILE"
        sleep 30
        continue
    fi
    
    # Check for file events in agent-reports
    echo "$response" | jq -r '.[] | select(.type == "ItemFinished" or .type == "ItemStarted") | select(.data.folder | contains("libertaria-core")) | "\(.id)|\(.type)|\(.data.item)|\(.data.action)"' 2>/dev/null | while IFS='|' read -r event_id event_type item action; do
        
        if [[ "$item" == *"$WATCH_FOLDER"* ]]; then
            echo "[$(date)] EVENT: $event_type - $item ($action)" >> "$LOG_FILE"
            
            # Check if it's a Voxis report
            if [[ "$item" == *"voxis"* ]]; then
                echo "[$(date)] 🦞 NEW VOXIS REPORT: $item" >> "$LOG_FILE"
                # Could trigger: openclaw sessions_send to self or notification
            fi
            
            # Check if it's a coordination file
            if [[ "$item" == *"coordination"* ]] || [[ "$item" == *"peer-review"* ]]; then
                echo "[$(date)] 📋 COORDINATION FILE: $item" >> "$LOG_FILE"
            fi
        fi
        
        # Update last event ID
        if [ "$event_id" -gt "$LAST_EVENT_ID" ]; then
            LAST_EVENT_ID=$event_id
        fi
    done
    
    # Small delay to prevent hammering
    sleep 5
done
