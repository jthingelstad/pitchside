See AGENTS.md.

For Claude Code: the workstream's memory is `~/.claude/projects/-Users-otto-Projects-throwingwood/memory/`, and sessions start in `~/Projects/throwingwood`, so this file loads only when a session works here. Pass `model: "opus"` on every Agent call. Read sibling repos in place, never write in them from here, and do side work in a `git worktree`.
