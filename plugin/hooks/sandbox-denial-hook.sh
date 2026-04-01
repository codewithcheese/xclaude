#!/bin/bash
# sandbox-denial-hook.sh — Claude Code PostToolUseFailure hook for xclaude
#
# When a tool fails with a permission error inside the xclaude sandbox,
# queries the macOS unified log for recent Seatbelt denials and injects
# context back to Claude via additionalContext (system reminder).
#
# Loaded automatically via the xclaude plugin (--plugin-dir).
# The XCLAUDE_ACTIVE env var gates execution so it only fires under xclaude.

set -euo pipefail

# Only run inside xclaude sandbox
[[ "${XCLAUDE_ACTIVE:-}" == "1" ]] || exit 0

INPUT=$(cat)

# Check if the error anywhere in the input looks like a sandbox denial.
# "Operation not permitted" is the macOS sandbox error; "Permission denied"
# covers POSIX-level blocks that may also originate from Seatbelt.
if ! echo "$INPUT" | grep -qi "operation not permitted\|permission denied"; then
  exit 0
fi

# Read recent sandbox denials from the log file streamed by xclaude.
# xclaude starts `log stream` outside the sandbox and writes to this file,
# because /usr/bin/log refuses to run inside a sandbox.
# Filter by timestamp (last 5 seconds) to only show denials from the
# failing command, not background noise from earlier in the session.
DENIAL_LOG="${XCLAUDE_DENIAL_LOG:-}"
DENIALS=""
if [[ -n "$DENIAL_LOG" && -f "$DENIAL_LOG" ]]; then
  CUTOFF=$(date -v-5S '+%Y-%m-%d %H:%M:%S')
  DENIALS=$(tail -100 "$DENIAL_LOG" \
    | awk -v cutoff="$CUTOFF" 'substr($0,1,19) >= cutoff' \
    | grep "Sandbox:" \
    | grep -E "file-read-data|file-write|process-exec|forbidden-exec" \
    | grep -v "duplicate report" \
    | sed 's/^.*Sandbox: //' \
    | sort -u \
    | tail -20 || true)
fi

# Build the context message
MSG="Sandbox denial detected. You are running inside an xclaude macOS Seatbelt sandbox. The previous command failed because the sandbox blocked access to one or more paths."

if [[ -n "$DENIALS" ]]; then
  ESCAPED_DENIALS=$(echo "$DENIALS" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
  MSG="${MSG}\\n\\nRecent sandbox denials:\\n${ESCAPED_DENIALS}"
else
  MSG="${MSG}\\n\\nNo specific denials found in the system log."
fi

MSG="${MSG}\\n\\nINSTRUCTIONS (you MUST follow these):\\n1. NEVER suggest the user run commands outside the sandbox, use the ! prefix, or bypass the sandbox in any way.\\n2. First, consider if the operation can succeed differently within current permissions (e.g. local install instead of global, project-local paths instead of home paths).\\n3. If no alternative exists, invoke /debug-sandbox to analyze the denial and draft the minimum permission change.\\n4. NEVER attempt to bypass, disable, or work around the sandbox."

# Return JSON with additionalContext — exit 0 injects cleanly as a system reminder
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "${MSG}"
  }
}
EOF

exit 0
