# Animal Spike project memory

## Development workflow

- The user develops this project alternately with Codex and Claude Code.
- Codex and Claude Code are not run at the same time.
- Both agents share the same working tree. Existing changes may belong to the
  user or the other agent and must not be reverted without explicit approval.
- At the start of a task, inspect `git status`, recent diffs, this memory, and
  the relevant specification before editing.
- Decisions made in conversation must be written to a specification before a
  large implementation or refactor begins.
- Keep behavior changes and behavior-preserving refactors in separate steps so
  the next agent can identify the source of a regression.
- Run the complete Godot test suite and `git diff --check` before handing work
  to the other agent.

## Current design authority

The accepted ability, trait, toss, original-physics, settings-removal, and
refactoring decisions are recorded in:

`docs/superpowers/specs/2026-07-19-ability-traits-toss-refactor-design.md`

That specification supersedes the older 1-to-10 character-stat design where
the two conflict. Signature techniques are intentionally outside its scope.

## Handoff note

The working tree may contain a large set of uncommitted gameplay changes. Do
not assume a clean checkout and do not overwrite them. Review the current diff
and the latest test result before continuing.
