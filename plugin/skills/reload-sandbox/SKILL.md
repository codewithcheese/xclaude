---
name: reload-sandbox
description: Reload the xclaude sandbox profile after config changes (.xclaude, toolchains). Creates a reload sentinel and tells the user to exit so xclaude restarts with the updated profile.
---

!`touch "$XCLAUDE_RELOAD_SENTINEL"`

Reload queued. Tell the user:

> Reload queued. Exit claude now (type `/exit` or press Ctrl+C twice) and xclaude will automatically restart with the updated sandbox profile. Your conversation will resume where you left off.

Do not do anything else. Do not read or modify the `.xclaude` file. Do not attempt to kill the process.
