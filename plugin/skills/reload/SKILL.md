---
name: reload
description: Reload the xclaude sandbox profile after config changes (.xclaude, toolchains). Creates a reload sentinel and tells the user to exit so xclaude restarts with the updated profile.
allowed-tools: Bash(touch *)
---

# Reload xclaude sandbox profile

The user has changed their `.xclaude` config or toolchain settings and wants to reload the sandbox profile without losing their conversation.

## What to do

1. Run this command to create the reload sentinel file:

```bash
touch "$XCLAUDE_RELOAD_SENTINEL"
```

2. Tell the user:

> Reload queued. Exit claude now (type `/exit` or press Ctrl+C twice) and xclaude will automatically restart with the updated sandbox profile. Your conversation will resume where you left off.

That's it. Do not do anything else. Do not read or modify the `.xclaude` file. Do not attempt to kill the process.

## How it works

xclaude wraps claude in a restart loop. When claude exits, xclaude checks for the sentinel file. If present, it re-assembles the sandbox profile (re-reading `.xclaude` and toolchains) and relaunches claude with `--continue` to resume the conversation.
