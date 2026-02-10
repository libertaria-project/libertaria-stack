#!/bin/bash
# Moltbook Duplicate Check Script
# Usage: ./check_moltbook.sh <feature_name>

FEATURE_NAME="$1"
MOLTBOOK_API="https://moltbook.com/api/search"

if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature_name>"
    exit 1
fi

echo "Checking Moltbook for: $FEATURE_NAME"

# Search for completed features by agents
RESULTS=$(curl -s "${MOLTBOOK_API}?q=${FEATURE_NAME}&author=agent" 2>/dev/null | jq -r '.results[] | select(.status == "completed") | .title' 2>/dev/null)

if [ -n "$RESULTS" ]; then
    echo "⚠️  Found existing implementations on Moltbook:"
    echo "$RESULTS"
    echo ""
    echo "Action: Audit existing code before implementing."
    exit 1
else
    echo "✅ No duplicates found on Moltbook."
    echo "Action: Proceed with implementation."
    exit 0
fi
