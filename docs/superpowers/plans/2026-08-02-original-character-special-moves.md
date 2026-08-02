# 原作8キャラ必殺技 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 原作8キャラの全必殺技を、承認済み入力・発動条件・効果・ドライブ35消費で実装し、決定論ロールバック、CPU、表示まで一つの完成状態へ接続する。

**Architecture:** `SimState` を同期状態の正本とし、`special_ball.gd` が特殊球の排他的な状態遷移、`special_moves.gd` が入力判定と接触効果、`player_status.gd` が感電・泡・既存炎上の行動不能物理を担当する。`simulation.gd` はtick順序、`hit_resolver.gd` は通常接触との合成、`ball_physics.gd` は特殊球と通常球の統合、表示層は確定状態からセルを選ぶだけとする。

**Tech Stack:** Godot 4.6、GDScript、整数固定tick、決定論ロールバック、PowerShell正規テスト入口、Claude Codeレビュー

## Global Constraints

- 正式仕様は `docs/superpowers/specs/2026-08-02-original-character-special-moves-design.md` 446行、SHA-256 `657759f9ed91db64c7ddfcdaf322ab2e75567d0c84511e92c726be9e1da3da70`。
- 各タスク開始前に行数とSHA-256を照合し、不一致なら停止する。
- 発動はDボタン `IN_ABILITY1`、原作由来の方向・地上空中・高さ・接触条件を守る。
- 全必殺技の開始コストは35。PIYOの突風アタック派生だけは再入力不要、追加消費なし、ドライブ0でも成立する。
- サーブ中、バーンアウト中、コスト不足、範囲外、条件不一致では発動せず消費もしない。
- シミュレーションへfloatを追加しない。原作28.2Hz相当の時間と座標は仕様の整数式で変換する。
- 特殊球は同時に一種類だけ。選手の炎上・感電・泡は球状態と別に保持し、再付与は残り時間の最大値を採用する。
- 新しい同期整数は必ず直列化、復元、ハッシュ、リセット、プローブへ同時に接続する。
- 人間とCPUは同じ入力判定と消費APIを通す。CPUだけの発動条件や無料化を作らない。
- 各タスクは契約テストを先に赤くし、最小実装後に `run_tests.ps1` を終了コード0まで通す。
- 実装コミット前にClaude Codeへ仕様適合と回帰リスクのレビューを依頼し、指摘は仕様・原作解析・実コードで検証する。
- 隔離worktreeは使わず、現在の `codex/original-character-specials` ブランチで作業する。

## File Map

- Modify `src/sim/chars.gd`: 必殺技ID、入力種別、全8キャラの所有技、威力、防御分類。
- Modify `src/sim/sim_config.gd`, `data/rules.json`: 共通コスト、既定威力、感電・泡時間、原作tick換算元。
- Modify `src/sim/sim_state.gd`: 特殊球、選手状態、特殊動作、D入力ラッチの同期状態。
- Create `src/sim/special_ball.gd`: 特殊球の設定、解除、接触可否、軌道、保持、時間・高さ換算。
- Create `src/sim/special_moves.gd`: 入力条件選択、通常接触へ加える必殺効果、吸引・強化ブロック開始条件。
- Create `src/sim/player_status.gd`: 炎上・感電・泡の入力封印と決定論物理。
- Modify `src/sim/ball_physics.gd`: 特殊球ステップ、壁・ネット・床での中央解除、予測プローブ。
- Modify `src/sim/hit_resolver.gd`: 特殊入力、接触効果、突風派生、強化ブロック。
- Modify `src/sim/simulation.gd`: Dエッジ、特殊動作、状態物理、リセット順序。
- Modify `src/sim/sim_cpu.gd`: 合法な原作キャラ必殺入力を既存意思決定へ接続。
- Create `src/display/special_ball_visual.gd`: `ball_sheet.png` の特殊球セルを純粋選択。
- Modify `src/display/game_view.gd`, `src/display/anim_select.gd`: 球と感電・泡・炎上・特殊動作の表示優先順位。
- Add focused tests under `tests/unit/` and update serialization, catalog, sync, config, CPU, display tests.

---

### Task 1: 必殺技カタログと数値契約

**Files:**
- Modify: `src/sim/chars.gd`
- Modify: `src/sim/sim_config.gd`
- Modify: `data/rules.json`
- Modify: `tests/unit/test_chars.gd`
- Modify: `tests/unit/test_config.gd`
- Create: `tests/unit/test_original_special_catalog.gd`

**Interfaces:**
- Produces: `Chars.SUPER_*` 全効果ID、`Chars.SPECIAL_CONTACT_*`、`Chars.SPECIAL_DIR_*`
- Produces: `Chars.super_def(id) -> Dictionary`, `Chars.has_super(char_id, id) -> bool`
- Produces: `cfg.special_drive_cost`, `cfg.special_damage_default`, `cfg.shock_ticks`, `cfg.bubble_ticks`, `cfg.original_tick_rate_milli`

- [x] **Step 1: 正式仕様の行数とSHA-256を照合する**

```powershell
$p='docs/superpowers/specs/2026-08-02-original-character-special-moves-design.md'
(Get-Content -LiteralPath $p -Encoding UTF8).Count
(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
```

Expected: `446` と承認済みSHA-256が一致する。

- [x] **Step 2: 全8キャラ・全効果・数値の赤いテストを書く**

`test_original_special_catalog.gd` に、TOMEからUMAまでの所有技、条件、威力、防御分類を表駆動で列挙する。共有ゴースト、PIYO自動派生、複数入力を持つHITO・PIYO・UMEも漏れなく検査する。

```gdscript
func test_original_roster_owns_approved_specials() -> void:
    var expected := {
        Chars.CHAR_TOME: [Chars.SUPER_GHOST_BALL, Chars.SUPER_FLAME_ATTACK],
        Chars.CHAR_HITO: [Chars.SUPER_DISAPPEARING_BALL, Chars.SUPER_FEINT_BALL],
        Chars.CHAR_PIYO: [Chars.SUPER_GUST_BALL, Chars.SUPER_GUST_ATTACK],
        Chars.CHAR_UME: [Chars.SUPER_SNAKE_BALL, Chars.SUPER_BUMBLE_BALL],
        Chars.CHAR_CARBY: [Chars.SUPER_GHOST_BALL, Chars.SUPER_THUNDER_ATTACK],
        Chars.CHAR_DUO: [Chars.SUPER_SUCTION, Chars.SUPER_BUBBLE_ATTACK],
        Chars.CHAR_SEC1: [Chars.SUPER_TRANSFER_BALL, Chars.SUPER_SUBSPACE_BLOCK],
        Chars.CHAR_SEC2: [Chars.SUPER_REFRAIN_ATTACK],
    }
    for char_id in expected:
        for special_id in expected[char_id]:
            check(Chars.has_super(char_id, special_id), "承認済み所有技")
```

- [x] **Step 3: `run_tests.ps1` で未定義ID・設定だけが赤いことを確認する**

- [x] **Step 4: カタログと設定を最小実装する**

カタログの各項目へ `power`、`contacts`、`directions`、`original_height_y`、`defense_class` を持たせる。発動側が名前から推測しない構造にする。コスト35はカタログへ複製せず設定の共通値を参照する。

- [x] **Step 5: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/chars.gd src/sim/sim_config.gd data/rules.json tests/unit/test_chars.gd tests/unit/test_config.gd tests/unit/test_original_special_catalog.gd
git commit -m "feat: 原作キャラ必殺技カタログを追加"
```

---

### Task 2: 同期状態と特殊球の中央管理

**Files:**
- Modify: `src/sim/sim_state.gd`
- Create: `src/sim/special_ball.gd`
- Modify: `src/sim/ball_physics.gd`
- Modify: `src/sim/simulation.gd`
- Modify: `src/display/game_view.gd`
- Modify: `tests/unit/test_state.gd`
- Modify: `tests/unit/test_state_coverage.gd`
- Create: `tests/unit/test_special_ball_state.gd`
- Modify: `tests/unit/test_sync.gd`

**Interfaces:**
- Produces: `SpecialBall.set_special(s, id:int, owner_idx:int, origin_vx:int = 0) -> void`
- Produces: `SpecialBall.clear_special(s) -> void`
- Produces: `SpecialBall.is_contactable(s) -> bool`, `is_visible(s) -> bool`
- Produces: `SpecialBall.original_ticks(n:int, cfg) -> int`, `is_above_original_y(s, y:int, cfg) -> bool`
- Consumes: `BallPhysics._step_ball`, `predict_first_floor_x`, all rally/match reset paths

- [x] **Step 1: 新規状態の赤い往復・ハッシュ・リセット検査を書く**

選手へ `shock_ticks`、`bubble_ticks`、`special_action`、`special_action_ticks`、`ability_latch`、球へ `ball_special_id`、`ball_special_phase`、`ball_special_ticks`、`ball_special_owner_idx`、`ball_special_origin_vx`、`ball_held_by` を設定し、往復と一フィールド差ハッシュを検査する。所有者と保持者の未設定値は`-1`。同じテストでラリー終了、試合初期化、キャラ選択初期化の各入口を通し、全新規状態が0または`-1`へ戻ることを先に赤くする。

- [x] **Step 2: 特殊球APIの赤い不変条件テストを書く**

```gdscript
func test_setting_one_special_replaces_all_previous_special_state() -> void:
    SpecialBall.set_special(s, Chars.SUPER_GHOST_BALL, 1, 123)
    SpecialBall.set_special(s, Chars.SUPER_SNAKE_BALL, 2, -456)
    check_eq(s.ball_special_id, Chars.SUPER_SNAKE_BALL, "特殊球は排他的")
    check_eq(s.ball_special_owner_idx, 2, "所有者を更新")
    check_eq(s.ball_special_origin_vx, -456, "基準速度を更新")
    check_eq(s.ball_special_phase, 0, "前効果の段階を残さない")
```

時間変換6→13、10→21、16→34、20→43と、高さ境界の直前・同値・直後を整数クロス積で固定する。

- [x] **Step 3: 正規入口で赤を確認する**

- [x] **Step 4: `SimState` と `SpecialBall` を実装する**

旧 `ball_ghost`、`ball_flame` は新IDへ移し、互換用二重状態は残さない。`to_int_array` と `load_int_array` の宣言順を一致させる。新規選手状態を全リセット入口へ同時に接続し、後続Taskへ先送りしない。

- [x] **Step 5: BallPhysicsプローブと全リセットを同じAPIへ接続する**

`_BallProbe` に全特殊球状態を複写し、床予測も本番と同じ特殊軌道を進める。壁・ネット・床・得点・ラリー開始・試合開始は `clear_special` を通す。保持中は通常積分を行わない。Task 4までの橋渡しとして、ゴーストと炎は通常球積分をそのまま通す最小 `SpecialBall.step` を置き、現TOME試作の物理を欠落させない。`game_view.gd` も新IDから従来の点滅・炎セルを選ぶよう同時に移し、削除フィールドを参照させない。

- [x] **Step 6: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/sim_state.gd src/sim/special_ball.gd src/sim/ball_physics.gd src/sim/simulation.gd src/display/game_view.gd tests/unit/test_state.gd tests/unit/test_state_coverage.gd tests/unit/test_special_ball_state.gd tests/unit/test_sync.gd
git commit -m "feat: 必殺技の同期状態と特殊球基盤を追加"
```

---

### Task 3: 共通入力判定と単発接触技

**Files:**
- Create: `src/sim/special_moves.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/simulation.gd`
- Create: `tests/unit/test_original_special_inputs.gd`
- Modify: `tests/unit/test_super_catalog.gd`

**Interfaces:**
- Produces: `SpecialMoves.select_hit_special(s, actor:int, input:int, cfg) -> int`
- Produces: `SpecialMoves.can_activate(s, actor:int, special_id:int, cfg) -> bool`
- Produces: `SpecialMoves.commit_cost(p, cfg) -> bool`
- Consumes: `CombatResources.can_pay/spend_committed`, `Chars.super_def`, `IN_ABILITY1`

- [x] **Step 1: 全入力組み合わせを表駆動で赤くする**

各技について正しい地上空中、方向、ボール高さ、味方球、接触範囲を正例にし、Dなし、逆方向、境界外、サーブ、バーンアウト、34、飛びつき中を負例にする。左右チームのForward/Back反転も固定する。

- [x] **Step 2: D入力と不成立時無消費の赤い検査を書く**

D入力は接触成立tickだけ一度処理され、失敗時35を引かないこと、成功時だけ35減ること、Dと通常ACTIONが同時でも技優先順位が一意であることを検査する。Dの押下エッジは真・亜空間ブロックの解放だけに使い、通常の打球型必殺技へ追加条件にしない。

- [x] **Step 3: 正規入口で赤を確認する**

- [x] **Step 4: カタログ駆動の選択と支払いを実装する**

地上接触はゴースト、消える球、フェイント、突風球、蛇球、ぶんぶん球。空中接触は炎、空中消える球、味方球突風/ぶんぶん、雷、泡、転送、リフレインを選ぶ。通常打球計算を先に成立させ、特殊効果はその確定速度・威力へ重ねる。

- [x] **Step 5: 既存TOME試作を新経路へ移し二重処理を削除する**

旧 `_special_for_input` と旧フラグ分岐を残さず、新APIだけで既存テストを満たす。このTaskでは発動・ID設定・既存TOMEの通常物理継続までを完成条件とし、消える球など新規の時間軌道はTask 4の赤テストまで未実行のIDとして保持する。Task 3の既存テストを軌道完成の代用にしない。

- [x] **Step 6: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/special_moves.gd src/sim/hit_resolver.gd src/sim/simulation.gd tests/unit/test_original_special_inputs.gd tests/unit/test_super_catalog.gd
git commit -m "feat: 原作必殺技の入力と接触を統合"
```

---

### Task 4: 原作特殊球の決定論軌道

**Files:**
- Modify: `src/sim/special_ball.gd`
- Modify: `src/sim/ball_physics.gd`
- Create: `tests/unit/test_original_special_trajectories.gd`
- Modify: `tests/unit/test_ball_physics.gd`

**Interfaces:**
- Produces: `SpecialBall.step(s, cfg) -> bool`
- Produces: 効果別段階遷移。`true` は通常球積分を消費、`false` は通常積分を継続。

- [x] **Step 1: 軌道の境界tickを赤く固定する**

ゴーストは接触可能のまま点滅、消える球は21tickまで半速、その後不可視・非接触、下降して原作y224相当を越えた時だけ復帰。転送は最大13tickまたは原作y240相当、フェイントは遅延後再開。突風・蛇は基準速度を保持して波形、リフレインは承認済み遅延と攻撃不能を検査する。

リフレインの待機開始にはレシーブ結果が必要なため、その境界検査は正式設計の実装順どおり
Task 5の防御結果テストで行う。Task 4では接触前の専用軌道6種だけを固定する。

- [x] **Step 2: 同一seed・snapshot復元後の軌道一致を赤くする**

各効果について途中snapshotから60tick進め、位置、速度、段階、乱数、状態ハッシュが連続実行と一致することを検査する。

- [x] **Step 3: 正規入口で赤を確認する**

- [x] **Step 4: 効果別の整数状態機械を実装する**

効果ごとの残り時間を別フィールドへ増殖させず、ID・phase・ticks・origin velocityだけで進める。波形や分岐乱数は状態の決定論RNGだけを使用する。

- [x] **Step 5: 通常物理との境界を実測する**

特殊処理が通常積分を消費するtickでは重力・位置更新を二重適用しない。終了tickは同tick中に通常積分へ戻すか次tickから戻すかを仕様テストで一意にする。

- [x] **Step 6: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/special_ball.gd src/sim/ball_physics.gd tests/unit/test_original_special_trajectories.gd tests/unit/test_ball_physics.gd
git commit -m "feat: 原作必殺球の決定論軌道を実装"
```

---

### Task 5: 派生攻撃、防御結果、感電・泡状態

**Files:**
- Create: `src/sim/player_status.gd`
- Modify: `src/sim/player_movement.gd`
- Modify: `src/sim/special_moves.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/simulation.gd`
- Create: `tests/unit/test_original_special_combat.gd`
- Create: `tests/unit/test_player_status.gd`
- Modify: `tests/unit/test_absolute_damage.gd`

**Interfaces:**
- Produces: `PlayerStatus.input_locked(p) -> bool`
- Produces: `PlayerStatus.step(p, cfg, team:int, state_tick:int, actor:int, rng:int) -> bool`
- Produces: `PlayerStatus.apply_shock(p, team:int, cfg)`, `apply_bubble(p, cfg)`
- Consumes: 通常ガード/ジャスト/体力/スタン処理、特殊球ID、PIYO通常空中攻撃

- [x] **Step 1: 攻撃と防御の結果表を赤くする**

通常必殺22、炎40、泡/リフレイン11、非ダメージ0を固定する。防御分類ごとに通常レシーブ、ジャスト、ブロック、アタック返しの可否と、接触後に特殊球が解除される条件を検査する。

- [x] **Step 2: PIYO自動派生を赤くする**

任意のPIYOが突風球へ通常空中アタックすると突風アタックになり、D不要、追加消費なし、ドライブ0でも成立する。地上、ブロック、レシーブ、飛びつき、別キャラ、再入では成立しない。

- [x] **Step 3: 感電と泡の物理・入力封印を赤くする**

感電は60tick、小さく後方上へ動き、摩擦・重力・床反発を整数で進める。泡は60tick、34tick周期の横波と決定論RNGを使い上昇し、上端でも終了する。再付与は`max`。どちらも最終tickまで入力・接触・ブロック不能。

ラリー終了、試合初期化、キャラ選択初期化で感電・泡が必ず0へ戻る赤テストもここへ追加する。Task 2で作った汎用リセット接続が、実際の付与後にも働くことを確認する。

- [x] **Step 4: 正規入口で赤を確認する**

- [x] **Step 5: `PlayerStatus` と接触効果を最小実装する**

既存炎上は互換性を壊さぬよう `PlayerMovement` から同じヘルパーを通す。優先順位はスタン、泡、感電、炎上、通常。状態tick中にタイマーを先に0へして入力が通る事故を防ぐ。

- [x] **Step 6: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/player_status.gd src/sim/player_movement.gd src/sim/special_moves.gd src/sim/hit_resolver.gd src/sim/simulation.gd tests/unit/test_original_special_combat.gd tests/unit/test_player_status.gd tests/unit/test_absolute_damage.gd
git commit -m "feat: 必殺攻撃と感電泡状態を実装"
```

---

### Task 6: DUO吸引とALIEN真亜空間ブロック

**Files:**
- Modify: `src/sim/special_moves.gd`
- Modify: `src/sim/special_ball.gd`
- Modify: `src/sim/simulation.gd`
- Modify: `src/sim/hit_resolver.gd`
- Create: `tests/unit/test_original_special_actions.gd`

**Interfaces:**
- Produces: `SpecialMoves.try_start_action(s, actor:int, input:int, cfg) -> bool`
- Produces: `SpecialMoves.step_action(s, actor:int, input:int, cfg) -> bool`
- Produces: `SpecialMoves.try_enhance_block(s, actor:int, input:int, cfg) -> bool`

- [x] **Step 1: 吸引の開始・継続・中断を赤くする**

DUOの空中Back+D、35支払い、球をDUO方向へ引くこと、終了・着地・被弾・得点で解除すること、球への作用でありDUO自身を移動させないことを検査する。

- [x] **Step 2: 強化ブロックの成功後状態を赤くする**

ALIENのForward+ACTION+Dが通常ブロック接触に成功した場合だけ35を払い、通常ブロックの反射・ダメージ結果を先に確定してから最大43tick保持する。保持中は方向入力で選手と球を同時移動し、新しいボタンエッジか時間切れで保持前の確定速度をそのまま再開する。

- [x] **Step 3: 失敗境界を赤くする**

空振り、通常ブロック不成立、34、バーンアウト、サーブ、被状態、D保持の再エッジなしでは強化しない。保持中の床予測・接触・通常積分を止める。

- [x] **Step 4: 正規入口で赤を確認し、両特殊動作を実装する**

特殊動作は `special_action` と `special_action_ticks` で排他的に管理する。ALIENの保持者は `ball_held_by` を正本とし、解除APIで必ず`-1`へ戻す。

- [x] **Step 5: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/special_moves.gd src/sim/special_ball.gd src/sim/simulation.gd src/sim/hit_resolver.gd tests/unit/test_original_special_actions.gd
git commit -m "feat: 吸引と真亜空間ブロックを実装"
```

---

### Task 7: CPUと原作表示資産の接続

**Files:**
- Modify: `src/sim/sim_cpu.gd`
- Create: `src/display/special_ball_visual.gd`
- Modify: `src/display/game_view.gd`
- Modify: `src/display/anim_select.gd`
- Create: `tests/unit/test_original_special_cpu.gd`
- Create: `tests/unit/test_special_ball_visual.gd`
- Modify: `tests/unit/test_sprite_factory.gd`

**Interfaces:**
- Produces: `SpecialBallVisual.cell_for(s) -> int`, `uses_special_sheet(s) -> bool`
- Consumes: `ball_sheet.png` 12列x2行、原作キャラの `shock`、`burn`、`bubble`、`fly` 等の登録済みアニメ

- [ ] **Step 1: CPUが共通入力へ入る赤いテストを書く**

決定論seedで、各キャラが合法条件ならD複合入力を返し、不合法条件・34・バーンアウトでは返さないことを検査する。最終成立は人間と同じ `SpecialMoves` 判定へ通して確認する。

- [ ] **Step 2: 球セルと選手アニメ優先順位を赤くする**

`ball_sheet.png` の原作セルをID・phase・tickから純粋選択し、不可視期間は通常球も特殊球も非表示にする。選手は `stun > bubble > shock > burn > normal`、特殊動作中は対応する原作アニメを選ぶ。

- [ ] **Step 3: 正規入口で赤を確認する**

- [ ] **Step 4: CPU入力を既存意思決定の低優先選択肢として実装する**

サーブ、守備緊急行動、確実な通常接触を壊さず、必殺候補が合法な時だけD入力を返す。結果やコストをCPU側で直接変更しない。

- [ ] **Step 5: 特殊球Spriteと状態アニメを実装する**

旧 `_flame_ball` を汎用 `_special_ball` へ置換し、セル番号は `special_ball_visual.gd` だけで決める。sim状態を表示層から変更しない。

- [ ] **Step 6: 全件緑、Claudeレビュー、コミット**

```powershell
.\run_tests.ps1
git add src/sim/sim_cpu.gd src/display/special_ball_visual.gd src/display/game_view.gd src/display/anim_select.gd tests/unit/test_original_special_cpu.gd tests/unit/test_special_ball_visual.gd tests/unit/test_sprite_factory.gd
git commit -m "feat: 原作必殺技のCPUと表示を接続"
```

---

### Task 8: 統合回帰、決定論、資料の完了

**Files:**
- Modify: `tests/unit/test_sync.gd`
- Modify: `tests/unit/test_state_coverage.gd`
- Modify: `tests/perf/test_performance.gd` if measured gate requires fixture update
- Modify: `docs/project-memory.md`
- Modify: `docs/superpowers/specs/2026-08-02-original-character-special-moves-design.md` only for implementation result appendix without changing contract
- Modify: this plan checkbox state

- [ ] **Step 1: 16発動経路の統合シナリオを追加する**

8キャラの全入力経路を少なくとも一度通し、開始、35消費、特殊状態、接触結果、終了、ラリーリセットを検査する。共有技と複数入力は両経路を通す。

- [ ] **Step 2: snapshot、hash、probe、再試合を検査する**

各特殊状態の途中snapshotから同じ入力列を再生し、毎tickハッシュ一致。床予測が本番と一致。得点後と再試合後に特殊球、保持、選手状態、Dラッチが残らない。

- [ ] **Step 3: 固定配列と性能警報を実測する**

直列化長、同期ゴールデン、CPU決定論ゴールデン、性能中央値を比較し、意図した状態追加以外の差なら停止する。ゴールデン変更は旧値、新値、原因を記録する。

- [ ] **Step 4: プレースホルダーと旧経路を検索する**

```powershell
rg -n "TODO|TBD|ball_ghost|ball_flame|pilot_super|temporary|後で実装" src tests docs/superpowers/specs/2026-08-02-original-character-special-moves-design.md
```

Expected: 今回範囲の未実装表現と旧試作経路が0件。無関係の既存ヒットは理由を記録する。

- [ ] **Step 5: Claude Codeへ最終差分レビューを依頼する**

仕様446行、全差分、テスト結果を渡し、入力、消費、原作状態遷移、決定論、リセット、CPU/人間共通性、表示漏れを確認する。指摘は証拠で採否を決め、必要なら赤テストから直す。

- [ ] **Step 6: 正規全件検証を行う**

```powershell
.\run_tests.ps1
```

Expected: 全件合格、`SCRIPT ERROR summary: 0 occurrence(s)`。件数、所要時間、未検証事項を記録する。

- [ ] **Step 7: 設計書の実装結果を記録し最終コミットする**

実装ファイル、全技の成立経路、テスト名、最終行数・SHA-256、変更全件を記録する。契約本文を変えない。

```powershell
git add docs/project-memory.md docs/superpowers/specs/2026-08-02-original-character-special-moves-design.md docs/superpowers/plans/2026-08-02-original-character-special-moves.md tests
git commit -m "docs: 原作キャラ必殺技の実装結果を記録"
git status --short
```

Expected: 作業ツリーがclean。pushとmainへの統合はユーザー指示まで行わない。
