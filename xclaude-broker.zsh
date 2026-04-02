#!/bin/zsh
# xclaude-broker — permission dialog broker for xclaude
#
# Runs OUTSIDE the sandbox as a background process. Listens for
# permission requests from Claude (inside the sandbox) via named
# pipes and presents native macOS dialogs for user approval.
#
# Protocol:
#   Claude writes JSON to $XCLAUDE_REQ_FIFO
#   Broker validates, shows dialog, writes JSON to $XCLAUDE_RESP_FIFO
#
# Actions:
#   add    — append a DSL rule to .xclaude
#   remove — delete a matching rule from .xclaude
#   exec   — run a command outside the sandbox
#
# Started by xclaude (the launcher) before entering sandbox-exec.
# Killed on exit by xclaude cleanup.

set -euo pipefail

# ── Arguments ────────────────────────────────────────────────
# Usage: xclaude-broker.zsh <req_fifo> <resp_fifo> <project_dir> <xclaude_dir>
readonly REQ_FIFO="$1"
readonly RESP_FIFO="$2"
readonly PROJECT_DIR="$3"
readonly XCLAUDE_DIR="$4"

# Source the library for validation functions
readonly __xclaude_dir="$XCLAUDE_DIR"
source "${XCLAUDE_DIR}/xclaude.lib.zsh"

readonly XCLAUDE_FILE="${PROJECT_DIR}/.xclaude"

# ── Shell metacharacter check ────────────────────────────────
# Rejects commands containing shell expansion/interpolation chars.
# The exec action must use literal strings only.
__broker_has_shell_metachar() {
  local s="$1"
  # Check for: $ ` | ; && || > < * ? ! ~
  # Also catches $( and ${
  [[ "$s" =~ [\$\`\|\;\>\<\*\?\!~] ]] && return 0
  [[ "$s" =~ '&&' ]] && return 0
  [[ "$s" =~ '\|\|' ]] && return 0
  return 1
}

# ── Rule explanation ─────────────────────────────────────────
# Derives a human-readable explanation from a DSL rule.
# This is the source of truth — NOT Claude's description.
__broker_explain_rule() {
  local rule="$1"
  local verb="${rule%% *}"
  local arg="${rule#* }"

  case "$verb" in
    tool)
      echo "Activate toolchain: ${arg} (grants read/write/exec per toolchains/${arg}.sb)"
      ;;
    allow-read)
      echo "Grant READ access to ${arg} and all contents"
      ;;
    allow-write)
      echo "Grant READ + WRITE access to ${arg} and all contents"
      ;;
    allow-exec)
      echo "Grant READ + EXECUTE access to ${arg} and all contents"
      ;;
    *)
      echo "Unknown directive: ${verb}"
      ;;
  esac
}

# ── macOS dialog ─────────────────────────────────────────────
# Shows a native macOS dialog via osascript. Returns 0 if user
# clicks Allow, 1 if Deny or cancels.
__broker_show_dialog() {
  local title="$1"
  local message="$2"

  local result
  result=$(osascript -e "
    set dialogResult to display dialog \"${message}\" ¬
      with title \"${title}\" ¬
      buttons {\"Deny\", \"Allow\"} ¬
      default button \"Deny\" ¬
      with icon caution ¬
      giving up after 120
    return button returned of dialogResult
  " 2>/dev/null) || return 1

  [[ "$result" == "Allow" ]] && return 0
  return 1
}

# ── JSON helpers ─────────────────────────────────────────────
# Minimal JSON field extraction (avoids jq dependency).
# Only handles flat string values — sufficient for our protocol.
__broker_json_get() {
  local json="$1" key="$2"
  # Extract "key": "value" — handles escaped quotes in value
  local value
  value=$(echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
  echo "$value"
}

# Extract a JSON array of strings: "key": ["a", "b"] → "a" newline "b"
__broker_json_get_array() {
  local json="$1" key="$2"
  # Extract the array content between [ and ]
  local arr
  arr=$(echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" | head -1)
  [[ -z "$arr" ]] && return
  # Extract each quoted string element
  echo "$arr" | grep -oE '"[^"]*"' | sed 's/^"//; s/"$//'
}

__broker_json_response() {
  local status="$1"
  shift
  if [[ "$status" == "error" ]]; then
    printf '{"status":"error","message":"%s"}\n' "$1"
  elif [[ "$status" == "approved" && $# -gt 0 ]]; then
    # For exec: include stdout, stderr, exit_code
    local stdout="$1" stderr="$2" exit_code="$3"
    # Escape for JSON: backslashes, quotes, newlines, tabs
    stdout=$(printf '%s' "$stdout" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' '\a' | sed 's/\a/\\n/g' | head -c 4096)
    stderr=$(printf '%s' "$stderr" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' '\a' | sed 's/\a/\\n/g' | head -c 4096)
    printf '{"status":"approved","stdout":"%s","stderr":"%s","exit_code":%s}\n' \
      "$stdout" "$stderr" "$exit_code"
  else
    printf '{"status":"%s"}\n' "$status"
  fi
}

# ── Escape string for osascript ──────────────────────────────
# Escapes backslashes and double quotes for AppleScript strings.
__broker_escape_applescript() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  echo "$s"
}

# ── Action handlers ──────────────────────────────────────────

__broker_handle_add() {
  local rule="$1" reason="$2"

  # Validate the rule through the same pipeline as .xclaude files
  local validated
  validated=$(echo "$rule" | __xclaude_validate 2>&1) || {
    __broker_json_response "error" "Validation failed: ${validated}"
    return
  }

  # Check if rule already exists in .xclaude
  if [[ -f "$XCLAUDE_FILE" ]]; then
    if grep -qFx "$rule" "$XCLAUDE_FILE" 2>/dev/null; then
      __broker_json_response "error" "Rule already exists in .xclaude"
      return
    fi
  fi

  # Build dialog message
  local explanation
  explanation="$(__broker_explain_rule "$rule")"
  local safe_rule safe_explanation safe_reason
  safe_rule="$(__broker_escape_applescript "$rule")"
  safe_explanation="$(__broker_escape_applescript "$explanation")"
  safe_reason="$(__broker_escape_applescript "$reason")"

  local message="ADD SANDBOX RULE

Rule: ${safe_rule}

${safe_explanation}

Claude's stated reason: ${safe_reason}

This change takes effect on next xclaude restart."

  if __broker_show_dialog "xclaude — Add Permission" "$message"; then
    # Append the rule to .xclaude (create if needed)
    if [[ ! -f "$XCLAUDE_FILE" ]]; then
      echo "$rule" > "$XCLAUDE_FILE"
    else
      echo "$rule" >> "$XCLAUDE_FILE"
    fi
    __broker_json_response "approved"
  else
    __broker_json_response "denied"
  fi
}

__broker_handle_remove() {
  local rule="$1" reason="$2"

  # Check the rule exists
  if [[ ! -f "$XCLAUDE_FILE" ]]; then
    __broker_json_response "error" "No .xclaude file exists"
    return
  fi
  if ! grep -qFx "$rule" "$XCLAUDE_FILE" 2>/dev/null; then
    __broker_json_response "error" "Rule not found in .xclaude"
    return
  fi

  # Build dialog message
  local explanation
  explanation="$(__broker_explain_rule "$rule")"
  local safe_rule safe_explanation safe_reason
  safe_rule="$(__broker_escape_applescript "$rule")"
  safe_explanation="$(__broker_escape_applescript "$explanation")"
  safe_reason="$(__broker_escape_applescript "$reason")"

  local message="REMOVE SANDBOX RULE

Rule: ${safe_rule}

Currently grants: ${safe_explanation}

Claude's stated reason: ${safe_reason}

This change takes effect on next xclaude restart."

  if __broker_show_dialog "xclaude — Remove Permission" "$message"; then
    # Remove the exact line from .xclaude
    grep -vFx "$rule" "$XCLAUDE_FILE" > "${XCLAUDE_FILE}.tmp" 2>/dev/null || true
    mv "${XCLAUDE_FILE}.tmp" "$XCLAUDE_FILE"
    # Clean up empty file
    if [[ ! -s "$XCLAUDE_FILE" ]]; then
      rm -f "$XCLAUDE_FILE"
    fi
    __broker_json_response "approved"
  else
    __broker_json_response "denied"
  fi
}

__broker_handle_exec() {
  local json="$1" reason="$2"

  # Extract command array
  local -a cmd_parts
  local part
  while IFS= read -r part; do
    [[ -n "$part" ]] && cmd_parts+=("$part")
  done < <(__broker_json_get_array "$json" "command")

  if (( ${#cmd_parts[@]} == 0 )); then
    __broker_json_response "error" "No command specified"
    return
  fi

  # Check each part for shell metacharacters
  for part in "${cmd_parts[@]}"; do
    if __broker_has_shell_metachar "$part"; then
      __broker_json_response "error" "Command contains shell metacharacters — use literal strings only"
      return
    fi
  done

  # Build display string for the command
  local cmd_display="${cmd_parts[*]}"
  local safe_cmd safe_reason
  safe_cmd="$(__broker_escape_applescript "$cmd_display")"
  safe_reason="$(__broker_escape_applescript "$reason")"

  local message="RUN OUTSIDE SANDBOX

Command: ${safe_cmd}

This command will run outside the sandbox with your normal user permissions.

Claude's stated reason: ${safe_reason}"

  if __broker_show_dialog "xclaude — Run Command" "$message"; then
    # Run the command, capture output
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    local exit_code=0

    # Execute with the command array — no shell expansion
    (cd "$PROJECT_DIR" && "${cmd_parts[@]}" > "$stdout_file" 2> "$stderr_file") || exit_code=$?

    local stdout stderr
    stdout=$(cat "$stdout_file" 2>/dev/null || echo "")
    stderr=$(cat "$stderr_file" 2>/dev/null || echo "")
    rm -f "$stdout_file" "$stderr_file"

    __broker_json_response "approved" "$stdout" "$stderr" "$exit_code"
  else
    __broker_json_response "denied"
  fi
}

# ── Main loop ────────────────────────────────────────────────
# Reads requests from the FIFO in a loop. Each request is a
# single line of JSON. The loop exits when the FIFO is removed
# (xclaude cleanup) or on read error.

while true; do
  # Blocking read — waits until a writer opens the FIFO
  local request
  if ! IFS= read -r request < "$REQ_FIFO" 2>/dev/null; then
    # FIFO removed or broken — exit cleanly
    break
  fi

  [[ -z "$request" ]] && continue

  # Extract fields
  local action reason
  action=$(__broker_json_get "$request" "action")
  reason=$(__broker_json_get "$request" "reason")

  # Default reason if empty
  [[ -z "$reason" ]] && reason="(no reason provided)"

  # Dispatch
  local response
  case "$action" in
    add)
      local rule
      rule=$(__broker_json_get "$request" "rule")
      if [[ -z "$rule" ]]; then
        response=$(__broker_json_response "error" "Missing 'rule' field")
      else
        response=$(__broker_handle_add "$rule" "$reason")
      fi
      ;;
    remove)
      local rule
      rule=$(__broker_json_get "$request" "rule")
      if [[ -z "$rule" ]]; then
        response=$(__broker_json_response "error" "Missing 'rule' field")
      else
        response=$(__broker_handle_remove "$rule" "$reason")
      fi
      ;;
    exec)
      response=$(__broker_handle_exec "$request" "$reason")
      ;;
    *)
      response=$(__broker_json_response "error" "Unknown action: ${action}")
      ;;
  esac

  # Write response to the response FIFO
  echo "$response" > "$RESP_FIFO"
done
