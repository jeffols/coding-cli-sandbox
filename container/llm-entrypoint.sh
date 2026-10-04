#!/bin/sh
# Usage: llm-entrypoint <pi|codex> [args...]
# Renders the tool's provider config from LLM_* env vars, then execs the tool.
set -eu
tool="$1"
shift
node /usr/local/lib/pi-sandbox/llm-config.js "$tool"
exec "$tool" "$@"
