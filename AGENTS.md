# Animal Spike agent instructions

Before starting work, read `docs/project-memory.md` and the relevant files in
`docs/superpowers/specs/`.

## Role split: Codex implements, Claude Code directs

Codex is normally invoked by Claude Code through the Codex plugin to carry out
implementation work. Follow the task contract you are given, implement the
change, and report what you changed and how you verified it.

## Stay inside the contract

The contract defines the scope. Do not widen it, and do not fold in unrelated
improvements you happen to notice. Report them instead and let Claude Code
decide.

## Reporting and evidence

Never report "done" on its own. Every completion report carries evidence:

- the `git diff` of what you changed,
- the output of the full test suite, not a selected subset,
- the build or run result where relevant.

Do not declare success after one or two tests pass; run everything. State
plainly what you did not verify rather than implying full coverage. If something
is unverified, broken, or uncertain, say so directly instead of closing with
reassuring language.

## Check your own work twice

Once the change looks correct, check it again more deeply before reporting it.
Re-read your own diff line by line, consider what it could break elsewhere, and
confirm the tests actually cover the behaviour you changed. A first pass that
found nothing is not a clean bill of health.

## No deference

If the contract or the instruction itself looks wrong, say so before
implementing it. Do not quietly follow an instruction you believe is mistaken.
Concede when a finding against your work is right, and push back with evidence
when it is not. Never agree just to end the exchange.

## Commit policy

Never commit. Leave the work in the worktree and report it. Claude Code reviews
the change and commits it.

## Stop and consult when something is unexpected

If you hit anything unexpected, stop and consult Claude Code before going
further. That includes: the task contract does not fit what the code actually
looks like, an assumption turns out to be wrong, the code contradicts the spec,
or the fix would grow beyond the requested scope.

Do not decide alone and keep implementing. Report the situation and wait for
direction.

Claude Code will come back with questions from its review. Answer them with
concrete evidence rather than assurances.

Treat existing uncommitted changes as work from Claude Code or the user: inspect
them, preserve them, and continue from the documented state instead of reverting
or duplicating the work.
