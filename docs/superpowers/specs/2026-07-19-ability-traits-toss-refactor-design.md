# Ability, trait, toss, and refactoring design

Date: 2026-07-19
Status: accepted gameplay decisions; implementation pending

## Collaboration context

Animal Spike is developed alternately with Codex and Claude Code. The agents
are not run simultaneously, but they use the same working tree. Each agent must
read `AGENTS.md` or `CLAUDE.md`, `docs/project-memory.md`, this specification,
and the current diff before changing code. Existing work must be preserved.

## Goals

- Replace opaque 1-to-10 player-facing stats with five A-to-E base abilities.
- Express exceptional strengths and weaknesses as named positive or negative
  traits.
- Make character differences understandable without hidden per-action scatter.
- Move toss assistance from a global checkbox to the `トス上手` trait.
- Adopt the confirmed original wall, net-top, block, and toss principles.
- Establish module boundaries before adding the new behavior.

Signature techniques, including Mario's currently implemented techniques, are
not redesigned here.

## Base abilities

The player-facing base abilities are `パワー`, `ジャンプ`, `スピード`,
`ブレーキ`, and `ガード`. Rank order is A, B, C, D, E. C is the standard.

| Rank | Power | Jump height | Speed | Stopping distance | Guard |
|---|---:|---:|---:|---:|---:|
| A | 150% | 155px | 120% | 60% | 150% |
| B | 125% | 145px | 110% | 80% | 125% |
| C | 100% | 135px | 100% | 100% | 100% |
| D | 75% | 120px | 90% | 125% | 75% |
| E | 50% | 100px | 80% | 150% | 50% |

Higher brake rank means shorter stopping distance. Background lines were only
used to discuss jump height; runtime physics uses pixel values and does not
depend on stage art.

For the first comparison build, every selectable character uses rank C for all
five abilities. Weight is also standard for everyone. This deliberately removes
old Panda/Frog/Mario/Fox base-stat differences so trait effects can be judged in
isolation.

## Trait model

Traits are named exceptions, not ranked stats. Mutually opposite traits cannot
be assigned together. The character-select screen lists assigned traits as
plain names, for example `付与能力: トス上手、レシーブ上手`. Trait activation
does not require an extra HUD message, color, or sound.

The data model reserves identifiers for the following accepted catalog. Only
the five traits marked active below receive gameplay behavior in the first
implementation.

Positive catalog:

- `トス上手` (active)
- `レシーブ上手` (active)
- `柔らかい手`
- `ブロック上手`
- `ジャスト巧者`
- `強心臓`
- `鉄壁`
- `空中制御`
- `クイック`

Negative catalog:

- `トス下手` (active)
- `レシーブ下手` (active)
- `むらっけ` (active)
- `ブロック下手`
- `ノミの心臓`
- `打たれ弱い`
- `着地硬直`
- `急停止苦手`
- `空中不器用`

Dormant catalog entries have names and identifiers only. They are not displayed
unless assigned in a future implementation, and they must not silently modify
physics.

Initial assignments:

| Character | Traits |
|---|---|
| Mario | `トス上手`, `レシーブ上手` |
| Panda | `トス下手`, `レシーブ下手`, `むらっけ` |
| Fox | none |
| Frog | none |

## Active trait behavior

### Mura (`むらっけ`)

Every attack independently produces one of these final power multipliers:

- 10% chance: 50%
- 80% chance: 100%
- 10% chance: 150%

This applies to normal attacks, just attacks, and attack serves. There is no
streak prevention and no activation notification. The multiplier changes attack
power, not toss or receive power. The deterministic simulation RNG must make the
same result on every peer and rollback replay. CPU players do not know the roll
before attacking; all players and CPUs react to the resulting ball afterward.

The old rule that derived continuous attack scatter from attack level is removed.
Characters without `むらっけ` have no random attack-power scatter.

### Receive skill

Receive reach is multiplied only for actions classified as receives:

- `レシーブ上手`: 115%
- no receive trait: 100%
- `レシーブ下手`: 85%

It does not change toss, attack, or block reach. CPU reach checks use the same
trait-aware value as player hit detection.

### Toss skill

- `トス上手`: no low-toss failure; uses original-style landing-zone aim.
- no toss trait: no automatic aim and no low-toss failure.
- `トス下手`: no automatic aim; 30% chance that a toss reaches 70% of normal
  maximum height.

Low height is specified as apex height, not as an arbitrary initial-velocity
percentage. Physics derives the required vertical launch speed. Toss traits
apply to ground and air tosses, but never to receives. Attack power and weight
do not change toss strength.

## Original-style toss aiming

The original game chooses a destination zone, estimates flight time from the
vertical trajectory, and derives horizontal velocity from current position to
that zone. It does not continuously track the teammate's current position.

`トス上手` uses the same learnable fixed-zone principle. For the current 448px
court, zones come from configuration rather than hard-coded stage art:

- own back: 56px from the left boundary (mirrored for the right team)
- own front: 157px from the left boundary (mirrored for the right team)
- opponent front: the opposing team's mirrored front position

Input mapping:

- no horizontal direction: own front
- direction away from the net: own back
- direction toward the net: opponent front

The same target selection extends to air tosses as an Animal Spike consistency
rule; this extension is not claimed as a confirmed original-game behavior.
Horizontal velocity is recalculated from the chosen vertical trajectory so the
landing zone remains stable. Normal and unskilled characters keep direct,
unassisted output rather than receiving hidden global correction.

The air-neutral `フェイント` remains named and behaves as a soft attack, not a
toss to a teammate.

## Original rules made standard

- Blocks require net proximity plus net-direction and action input.
- Ground and air blocks are valid.
- Jumping alone never blocks.
- A block counts as one team touch.
- CPU blockers issue the same input as human players.
- Side-wall reflection always retains 50% horizontal velocity.
- A just/power ball that hits a side wall also loses its power state, preserving
  the previously accepted visible loss of momentum.
- The net top always uses the original bounce: falling vertical speed is halved
  and the ball is nudged away from the net.

## Settings removal

Remove the three development checkboxes:

- wall reflection original mode
- net-top original mode
- toss automatic correction

Remove `wall_half`, `net_top_original`, and `toss_assist` from default settings,
UI wiring, and physics overrides. On migration, erase these obsolete keys from
`user://settings.cfg`; there is no gameplay-progress save file. Toss assistance
is thereafter controlled only by `トス上手`.

## CPU behavior

CPU and human characters use the same base abilities, trait checks, receive
reach, toss resolver, attack roll, wall physics, and block rules. CPU planning
may inspect known character traits but never future random outcomes. Landing
prediction must consume the shared trajectory functions instead of duplicating
physics constants.

## Refactoring strategy

Use a staged refactor before implementing the accepted behavior. Do not perform
a full rewrite and do not add the new rules directly to the current monolith.

1. Add characterization tests for current hit intents, output velocities,
   collision ordering, CPU decisions, serialization, and settings propagation.
2. Extract modules without changing behavior. The full test suite and combined
   deterministic hash must remain unchanged during this step.
3. Introduce the A-to-E profile and trait data model.
4. Implement the accepted behavior one feature at a time, updating tests and the
   deterministic hash only for intentional behavior changes.
5. Remove obsolete stat, scatter, toggle, and migration code after replacements
   are verified.

Target responsibilities:

- `character_profile.gd`: ranks, weight class, traits, signature-technique bits
- `action_intent.gd`: input and state to receive/toss/attack/block/serve intent
- `hit_resolver.gd`: output trajectory, toss zones, low toss, Mura, hit effects
- `player_movement.gd`: movement, braking, jump, landing
- `ball_physics.gd`: gravity, walls, floor, net, block collision
- `status_resolver.gd`: guard, stun, flinch, recoil, push
- `serve_resolver.gd`: serve phases and attack serves
- `simulation.gd`: deterministic orchestration and state transitions

The first extraction should be deliberately narrow: action intent, hit
resolution, and ball physics are the highest-risk boundaries. Player/status/serve
extraction can follow after those are stable.

## Verification

- Every rank mapping and initial all-C roster is tested.
- Every active trait has positive, neutral, and negative control cases.
- Mura distribution is deterministic and covers normal, just, and attack serve.
- Toss-good zones are verified from both teams and from ground/air.
- Toss-bad produces exactly 70% target apex in 30% of deterministic samples.
- Receive reach uses 115%, 100%, and 85% only for receive intents.
- Removed settings no longer appear and obsolete keys are erased.
- Original wall, net-top, and block behavior is always active.
- CPU tests use the shared ability and trajectory rules.
- Serialization/state coverage and the 60-second synchronization test pass.
- The complete Godot suite passes with no script errors.
