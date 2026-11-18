#!/usr/bin/env bash
# Regenerates server/install-*.sh from the source files. Run after changing backend/main.py or node-agent/agent.py.
set -euo pipefail; cd "$(dirname "$0")/.."
cat server/parts/node-head.sh node-agent/agent.py server/parts/node-tail.sh > server/install-node.sh
cat server/parts/backend-head.sh backend/main.py server/parts/backend-tail.sh > server/install-backend.sh
chmod +x server/install-*.sh; bash -n server/install-node.sh; bash -n server/install-backend.sh; echo "installers rebuilt"
