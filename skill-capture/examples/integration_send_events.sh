#!/usr/bin/env bash
# Send one event to Skill Capture. Usage: SC_URL=http://localhost:3000 SC_TOKEN=sc_... ./send_events.sh
set -euo pipefail
curl -sS -X POST "${SC_URL:-http://localhost:3000}/api/v1/events" \
  -H "Authorization: Bearer ${SC_TOKEN:?set SC_TOKEN}" -H "Content-Type: application/json" \
  -d "{\"events\":[{\"action\":\"excel.run_macro:month_end\",\"label\":\"Run the month-end macro\",\"domain\":\"finance\",
       \"actor\":{\"id\":\"u-123\"},\"session\":\"s-1\",\"occurred_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
echo
