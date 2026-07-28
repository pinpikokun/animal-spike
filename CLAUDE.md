# Animal Spike Claude Code instructions

Remake of the PC-98 freeware "VOLLEY BALL 2on2".
Disassembly: `C:\work\PC98\vb2211-analysis\`.

## Before starting

Read `docs/remaining-tasks.md` — it holds the current work and is the single
source of truth for tasks. Read `docs/project-memory.md` and the one relevant
spec in `docs/superpowers/specs/` only when the task needs them.

Later tasks live in `docs/tasks-backlog.md` and past history in `docs/archive/`.
Do not read those unless the task calls for them.

**Specs are large — several run past 20 KB.** When you are only looking
something up, grep for the section you need instead of reading the file whole.

**The exception is the spec you are about to approve. Read that one in full.**
Approving it is the review step in Role split below, and you cannot review what
you skimmed.

## Role split

You decide the approach and the content of the design. Codex writes the spec
file. **You review and approve that spec. Only then does Codex implement it.**
You then verify the result (see **Verifying the work**) and commit. Codex never
commits, and a "done" or "fixed it" report is never accepted as evidence.

    you decide -> Codex writes the spec -> you approve and pin it
      -> Codex implements -> you verify -> you commit

**Review the spec before implementation, not after.** If you wait for the diff,
a misreading is already baked into the spec, the code, and the tests at once —
and the diff will look consistent with all three.

**Know what your review can and cannot catch.** You decided the content, so you
are not a neutral judge of whether the decision itself is right — only of
whether the spec says what you decided. You are neutral on implementation
convenience; Codex is not, because Codex implements next. For the decision
itself, ask Codex or the user.

When delegating to Codex, pass `--effort high` unless the user says otherwise.
Narrow the scope you allow it to read; an open-ended investigation can run 20
minutes without reaching a conclusion.

**Always pass `--write`. Consultations included, no exceptions.** Withholding it
does not make anything safer — the contract text does that, and you write the
contract every time ("spec only", "no tests, no Godot, no commit"). What
withholding it actually buys is a silent stall: on 2026-07-28 a consultation sent
without `--write` was followed by a spec job that died on "the workspace is
read-only" after 7 minutes 12 seconds, producing nothing. That was the second
time. Buy safety with the contract, never with the sandbox.

**`--background` alone gives you no completion notification. Arm a watcher in the
same breath.** The companion detaches the job from the harness, so Claude Code
sees only "the command exited" and has no way to learn the job finished. Left
like that, the user asking "what happened?" becomes the only thing that wakes
you. Right after launching, start a poll loop that exits when the job leaves
`running`, via `Bash(run_in_background: true)` — the harness owns that one and
wakes you when it exits. `status <id> --json` returns `{workspaceRoot, job}`;
read `job.status`. Do not reach for `Monitor`, which is built for repeated
events, not a single completion.

**Never touch the tree while Codex is reading it.** Run throwaway experiments in
a separate worktree. On 2026-07-28 a probe rewrote `simulation.gd` while a Codex
job was running `git diff` over the same path.

**An approved spec is frozen until the implementation lands.** Pin the version
(line count + SHA-256) when you approve it and hand that over. Do not edit it in
the meantime — not while Codex is reading it, not while Codex is implementing
from it. If it has to change, stop the implementation, change it, and approve it
again with a new pin.

## Original fidelity is the default

**If the original has a value or a mechanism, use it. Do not ask.**

Bring a proposal only when the deviation makes the game better or more
distinctly ours, and say in one sentence what changes for the player.

**Never reasons to deviate:** convenience, performance, maintainability, your
own uncertainty, "the code already works this way", "keeping it is safer"
(keeping is itself a deviation). Cover your risk with a loud failing test, not
by changing what the game does.

**When the original genuinely has nothing** (drive gauge, just-timing, ranks),
say so and decide it with the user. Per-second values cannot be converted at
all (the original's frame rate is unknown) and are settled by playing.

The user has restated this repeatedly. A violation is a serious error.

## Verifying the work

Read the real `git diff`, the real test output, the real build result. Require
the full test suite; never declare success on one or two tests.

Evidence ranks: environment state > tool call records > what the agent says. A
long, confident rebuttal is not proof the finding was wrong — put the rebuttal
and the finding side by side and judge them together.

## Golden hash: one green tree, one reason, one commit

**"The golden hash" is not one test, and it is not a fixed list either.** Several
tests pin behaviour to a hard-coded value. When one cause reaches several of them
they all move at once — that is not a rule violation, it is the same cause
reaching every pin. Re-take those together in one commit, **after** confirming
they share one cause and that nothing else is red.

**Work out which pins your change reaches, every time. Do not trust a list.**
This file used to name two tests as "the group that pins `state_hash()`". #88b-2
proved that framing wrong in both directions at once:
`test_hit_chain_second_golden` does pin `state_hash()` but **did not move**, and
`test_scatter_stream_snapshot` does not pin `state_hash()` but **did**. The first
one runs entirely at `tick=0 / rng=0 / aitick=0`, so the old and new RNG source
produce identical values and it cannot detect that class of change at all.

So the question is never "is this test in the golden list". It is "does this
change reach what this test actually pins". Answer it from the cause, and say in
the commit which pins you expected to move and which you did not.

**Never re-take a value that did not move.** If a pin you expected to move stayed
green, that is a finding about the test, not a formality to tidy up. Writing a
fresh value into it puts a number in the tree that no failure ever produced.

A golden hash is only evidence if you can point at the tree it came from. On
2026-07-27 that trace was lost: two updates were written into a single
uncommitted hunk on a tree that still held a broken feature, and the value ended
up in no commit at all (`git log --all -S<value>` returned zero). It had to be
retaken and the old value declared void. Rules, so it does not happen twice:

- **Re-take only from a tree where everything except the golden test is green.**
  One compile error or one unrelated red and the value is not evidence.
- **One logical change per re-take, one commit.** Never batch two reasons into
  one value. If two changes both moved it, land them separately.
- **Record old value, new value, reason, test count, and failure count** in the
  commit. Afterwards confirm `git log -S<new value>` finds that commit.
- **Never edit the value to make a test pass.** A mismatch is a finding: either
  the change was not the one you intended, or something else moved with it.
- When other unrelated work is uncommitted, take the value in a separate
  worktree instead of from the mixed tree.

## Speaking up

If the user's instruction or premise looks wrong, say so before acting.
When a judgement call is hard, consult Codex.
