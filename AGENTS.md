# Animal Spike agent instructions

Remake of the PC-98 freeware "VOLLEY BALL 2on2".

## Role split

Claude Code decides the content of the design. You write the spec file under
`docs/superpowers/specs/`, then **hand it over and wait for Claude Code to
approve it. Do not start implementing the moment the spec is written** — a
misreading that goes straight into code lands in the spec, the code, and the
tests at once, and the diff then looks consistent with all three.

After approval you implement it and report what you changed and how you
verified it. **Before you start, check the spec against the line count and
SHA-256 Claude Code pinned when approving it.** If it does not match, stop and
report it — never implement from a spec that changed after it was approved.

**Never commit** — leave the work in the worktree.

Writing the spec does not make the design yours.

Read `docs/project-memory.md` only when the task needs it. **When you implement
from a spec, read that spec in full** — even one you wrote yourself, because
you wrote it in a different session and do not remember it.

## Writing the spec

Write it so it can be implemented without guessing. For each behaviour state
the trigger condition, its priority against the others, the state transitions,
the formula, and the exceptions.

- **Separate what comes from the original from what we decided ourselves**, and
  say which is which.
- **Point at the code** where it already holds a constant or a formula. Copied
  values drift. Never write the same number in two places.
- **Say what must never happen**, not only the normal path.
- **Give the verification method and the pass condition.**
- **Write an open question as a stop, not as a blank.** A blank invites the
  implementer to guess; a stop makes them come back.
- **Make every decision findable by search.** Length is not the problem —
  decisions buried in prose are. Keep background and rules apart.

## Stop and consult

Stop and ask Claude Code when the contract is incomplete or contradictory, when
it does not fit the code, or when the work would grow beyond the requested
scope. Do not decide alone and keep going.

This applies while you are **writing the spec** as much as while you are
implementing. A gap in what you were told is a stop, not something to fill in.

## Do not substitute your own approach

Do not replace what the contract asks for because it is simpler, faster, safer,
or closer to the current code. If you believe it cannot work, stop and report
it. Do not implement your alternative.

**Do not invent numbers.** Every gameplay value comes from the contract or the
spec it points to. A value you chose yourself is a defect even if tests pass.
When the contract marks a value as provisional, keep it in one named place with
a comment saying so.

## Stay inside the contract

Do not widen the scope or fold in unrelated improvements. Report them and let
Claude Code decide.

**Never touch a hard-coded expected value that pins behaviour.**
`GOLDEN_COMBINED_HASH` in `tests/unit/test_sync.gd` is the obvious one, but it is
not the only one — `test_scatter_stream_snapshot` pins a 60-element RNG stream,
and other tests pin fixed arrays or hashes. All of them are regression alarms,
not values to keep in sync with the code. If one goes red, that is a finding:
report it and stop. Editing it to make the suite pass destroys the only evidence
that the change was the one intended. Claude Code re-takes them, from a tree where
everything else is green, in its own commit.

This also applies to values that are *not* hard-coded but are computed inside the
test from the same helper the production code uses. If the test recomputes the
expected result, it can agree with a broken implementation. Say so and stop
rather than papering over it.

## Reporting and evidence

Never report "done" on its own. List every change, not a summary, and state
plainly what you did not verify.

**Handing over a spec for review** — report the version you produced (line count
+ SHA-256) and every change you made. There is no diff and no test output at
this stage. Do not manufacture one.

**Reporting a finished implementation** — carry the `git diff`, the output of
the **full** test suite (not a subset), and the build or run result where
relevant.

## No deference

If the contract or instruction looks wrong, say so before implementing it.
Concede when a finding against your work is right; push back with evidence when
it is not. Never agree just to end the exchange.
