#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GF_ADMIN_USER:?GF_ADMIN_USER not set in .env}"
GRAFANA_PASS="${GF_ADMIN_PASSWORD:?GF_ADMIN_PASSWORD not set in .env}"
export BOT_TOKEN="${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set in .env}"
export CHAT_ID="${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID not set in .env}"

AUTH="${GRAFANA_USER}:${GRAFANA_PASS}"

EXISTING_UID=$(curl -sf -u "$AUTH" "${GRAFANA_URL}/api/v1/provisioning/contact-points" | \
  python3 -c "
import json, sys
cps = json.load(sys.stdin)
print(next((cp['uid'] for cp in cps if cp['name'] == 'Telegram'), ''))
" 2>/dev/null || echo "")

PAYLOAD=$(python3 << 'PYEOF'
import json, os

message = (
    "{{ if eq .Status \"firing\" }}🔴 FIRING{{ else }}✅ RESOLVED{{ end }}: "
    "{{ index .CommonLabels \"alertname\" }}\n"
    "\n"
    "{{ range .Alerts -}}"
    "{{ .Annotations.summary }}\n"
    "{{ .Annotations.description }}\n"
    "Severity: {{ index .Labels \"severity\" }}\n"
    "{{ end -}}"
)

print(json.dumps({
    "name": "Telegram",
    "type": "telegram",
    "settings": {
        "bottoken": os.environ["BOT_TOKEN"],
        "chatid":   os.environ["CHAT_ID"],
        "message":  message,
    },
    "disableResolveMessage": False,
}))
PYEOF
)

if [[ -n "$EXISTING_UID" ]]; then
  echo "Updating Telegram contact point (uid: $EXISTING_UID)..."
  curl -sf -X PUT "${GRAFANA_URL}/api/v1/provisioning/contact-points/${EXISTING_UID}" \
    -u "$AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$PAYLOAD"
else
  echo "Creating Telegram contact point..."
  curl -sf -X POST "${GRAFANA_URL}/api/v1/provisioning/contact-points" \
    -u "$AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$PAYLOAD"
fi
echo ""

echo "Configuring notification policy..."
curl -sf -X PUT "${GRAFANA_URL}/api/v1/provisioning/policies" \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -H "X-Disable-Provenance: true" \
  -d '{
    "receiver": "Telegram",
    "group_by": ["alertname", "routerboard_name"],
    "group_wait": "30s",
    "group_interval": "5m",
    "repeat_interval": "4h"
  }'
echo ""

echo "Done. Telegram alerting is configured."
