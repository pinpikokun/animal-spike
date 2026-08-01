# #70 操作体系の原作準拠化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 空中の上を通常アタック、下をジャスト可アタック、前を地上・空中共通ブロックへ変更し、空中トス3方向とCPU・表示を同じ操作契約へ揃える。

**Architecture:** `HitResolver` を入力分類と打球結果の正本とし、既存のintent配列に「ジャスト許可」を追加して上・下アタックの物理を分岐する。ブロックは前入力と文脈条件を `_is_active_block()` で一意に解決し、条件不成立時は通常の前トスへ戻す。CPUは人間と同じ入力ビットを選び、表示は既存 `hit_kind` にブロック種別を追加してsim状態から決定する。

**Tech Stack:** Godot 4.6 / GDScript / int固定小数点sim / PowerShellテスト入口 `run_tests.ps1`

## Global Constraints

- 承認正本は `docs/gameplay-controls.md` 154行、SHA-256 `8df55ff30dbe44aa5d4e7379c7120104c2f7b2be9ea63bccd3af4b1095382403`。
- 詳細設計は `docs/superpowers/specs/2026-07-25-controls-original-restoration-design.md` 244行、SHA-256 `4b52da50a4842b9f5f8cbaa41f752020ef2e4e202c20d5d7cf4b09f97545bdbb`。
- 隔離ワークツリーを作らず、既存ブランチ `codex/issue-70-controls-original` で作業する。
- 空中上+ボタンは常に通常アタック、空中下+ボタンだけがジャストアタックを許可する。
- 上と下の非ジャストアタックは着弾位置、速度、角度を一致させる。
- 上下同時入力は既存の上優先を維持し、ゲージを使わない通常アタックとして扱う。
- ブロックは地上・空中とも前+ボタンで、上下入力なし、相手球、ネット60px以内、自陣へ進む球の全条件を要求する。
- ブロック条件不成立時の前+ボタンは敵陣トスになる。
- 空中トスは後=自陣後方、なし=自陣前方、前=敵陣とし、3打目は全方向を敵陣へ返す。
- CPUはドライブ1本以上かつ非バーンアウトなら下、その他は上でアタックする。
- 能力値、CPU難易度、打球速度、ゲージ値、ガード値、レシーブ仕様を変更しない。
- 原作のブロック姿勢はセル9であるため、新画像を追加せず既存シートのセル9を使う。
- 固定ハッシュまたはゴールデン値が変化した場合は新旧値と原因を報告し、ユーザー承認まで更新しない。
- 各実装単位はテストを先に変更して赤を確認し、最小実装で緑へ戻す。

---

## File Structure

- `src/sim/hit_resolver.gd`: 入力分類、上・下アタック、前ブロック、空中トス3方向、ブロック成功種別を解決する。
- `src/sim/sim_state.gd`: 既存 `hit_kind` の値へブロック種別定数を追加する。
- `src/sim/sim_cpu.gd`: ゲージ別の上下アタックと前ブロック入力を選ぶ。
- `src/sim/sim_input.gd`: 入力ビットの説明を最終操作へ更新する。
- `src/display/input_poll.gd`: キーボード入力の説明を最終操作へ更新する。
- `src/display/anim_select.gd`: 地上・空中ブロック成功中にブロック姿勢を選ぶ。
- `src/display/sprite_factory.gd`: `block` アニメと代役連鎖を登録し、原作セル9を割り当てる。
- `tests/unit/test_controls_original.gd`: 最終操作の分類とブロック優先順位を固定する。
- `tests/unit/test_hit.gd`: 上下アタック、空中トス3方向、地上・空中ブロックの実打球を固定する。
- `tests/unit/test_drive_gauge.gd`: 上アタックが芯でもゲージを消費しないことを固定する。
- `tests/unit/test_cpu.gd`: CPUの前ブロックとゲージ別上下選択を固定する。
- `tests/unit/test_cpu_trial_shot.gd`: CPU候補生成が上下どちらでも共通物理を通ることを固定する。
- `tests/unit/test_anim_select.gd`: ブロック姿勢の優先順位を固定する。
- `tests/unit/test_sprite_factory.gd`: `block` のアニメ登録と代役契約を固定する。
- `docs/gameplay-controls.md`: 実装状況だけを完了へ更新する。
- `docs/tasks/70.md`: 実装結果、差分、検証、未検証事項を記録する。
- `docs/remaining-tasks.md`: #70を完了表示へ更新する。
- `docs/superpowers/specs/2026-07-25-controls-original-restoration-design.md`: Statusを実装済みへ更新する。

---

### Task 1: 上・下アタックのジャスト許可を分離する

**Files:**
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_drive_gauge.gd`
- Modify: `tests/unit/test_hit.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/sim_input.gd`
- Modify: `src/display/input_poll.gd`

**Interfaces:**
- Consumes: `_classify_intent(on_ground, input, d2, player_reach, serve_strike) -> Array[int]`
- Produces: intent配列 `[kind, hdir, up, allow_just]`。`allow_just=1` は空中下アタックだけ。

- [ ] **Step 1: 最終分類の失敗テストを書く**

`test_air_nine_grid_classifies_vertical_kind_and_horizontal_depth()` を、上段と下段の両方が `INTENT_AIR_SPIKE` になり、4要素目だけが異なる検査へ変更する。

```gdscript
var safe := HitResolver._classify_intent(
	0, SimInput.IN_ACTION | SimInput.IN_UP | row[0], 0, cfg.player_reach, false)
check_eq(safe[0], HitResolver.INTENT_AIR_SPIKE, "上段は通常アタック")
check_eq(safe[3], 0, "上段はジャスト不許可")
var wager := HitResolver._classify_intent(
	0, SimInput.IN_ACTION | SimInput.IN_DOWN | row[0], 0, cfg.player_reach, false)
check_eq(wager[0], HitResolver.INTENT_AIR_SPIKE, "下段はジャスト可アタック")
check_eq(wager[3], 1, "下段だけジャスト許可")
```

`test_drive_gauge.gd` へ、芯で上+ボタンを打っても `BALL_ATTACK_NORMAL`、自己消費0になる検査を追加する。`test_hit.gd` へ、上アタックと芯外し下アタックの最終速度が3方向すべて一致する検査を追加する。各方向で `preview_air_spike_velocity()` の予測値と `_apply_hit()` の実打球値を両方検査し、片方だけがジャスト不許可になる事故を防ぐ。

- [ ] **Step 2: 全件を実行して赤を確認する**

Run: `./run_tests.ps1`

Expected: 上入力が `INTENT_AIR_BLOCK` のため新しい分類検査が失敗し、上アタックの実打球検査も失敗する。既存テストの失敗は変更対象の期待値に限定される。

- [ ] **Step 3: intentのジャスト許可を最小実装する**

`_classify_intent()` の空中分岐を次の優先順位へ変更する。

```gdscript
if up == 1:
	return [INTENT_AIR_SPIKE, hdir, up, 0]
if input & IN_DOWN:
	return [INTENT_AIR_SPIKE, hdir, up, 1]
return [INTENT_AIR_TOSS, hdir, up, 0]
```

`preview_air_spike_velocity()` と `_apply_hit()` は、特殊技とバーンアウト条件を解決した後、`intent[3] == 0` なら `sweet=false` にする。これにより上アタックは通常倍率、通常慣性、通常属性を使い、下の非ジャスト結果と同一になる。入力コメントも上=通常アタック、下=ジャスト可アタックへ更新する。

空中上をブロックへ分類しなくなるため、参照がなくなる `INTENT_AIR_BLOCK` を削除する。ブロックはTask 2でintentではなく `_is_active_block()` の文脈判定だけが担当する。

- [ ] **Step 4: 全件を実行して緑を確認する**

Run: `./run_tests.ps1`

Expected: `561`件以上、失敗0、`SCRIPT ERROR summary: 0 occurrence(s)`。固定ハッシュ変化が出た場合はGlobal Constraintsの停止条件を適用する。

- [ ] **Step 5: コミットする**

```powershell
git add -- src/sim/hit_resolver.gd src/sim/sim_input.gd src/display/input_poll.gd tests/unit/test_controls_original.gd tests/unit/test_drive_gauge.gd tests/unit/test_hit.gd
git commit -m "feat: 空中上下で通常とジャスト可アタックを分ける"
```

---

### Task 2: 前+ボタンを地上・空中共通ブロックへ移す

**Files:**
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_hit.gd`
- Modify: `tests/unit/test_refactor_characterization.gd`
- Modify: `src/sim/hit_resolver.gd`

**Interfaces:**
- Consumes: `team_of(i)`, `SimStateScript._dir_of_team(team)`, `_is_active_block(s, i, input, cfg)`
- Produces: `_is_block_input(team: int, input: int) -> bool`。地上・空中共通の前+ボタン、上下なしだけを真にする。

- [ ] **Step 1: 前ブロックの失敗テストを書く**

`test_controls_original.gd` の旧「空中上だけブロック」検査を次へ置き換える。

```gdscript
var forward := SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
check(HitResolver._is_active_block(
	s, blocker_idx, SimInput.IN_ACTION | forward, cfg), "空中の前+ボタンでブロック")
p.on_ground = 1
check(HitResolver._is_active_block(
	s, blocker_idx, SimInput.IN_ACTION | forward, cfg), "地上の前+ボタンでもブロック")
check(not HitResolver._is_active_block(
	s, blocker_idx, SimInput.IN_ACTION | SimInput.IN_UP, cfg), "上+ボタンはブロックしない")
```

相手球でない、ネット60px外、球が自陣へ向かわない、上下入力ありの各境界と、条件不成立時に前トスとして実打球される検査を追加する。`test_hit.gd` は地上・空中の実ブロック反射を両チームで検査する。

- [ ] **Step 2: 全件を実行して赤を確認する**

Run: `./run_tests.ps1`

Expected: 前入力が旧ブロック条件に入らず、地上ブロックも拒否されるため新テストが失敗する。

- [ ] **Step 3: 文脈ブロックを最小実装する**

```gdscript
static func _is_block_input(team: int, input: int) -> bool:
	if (input & IN_ACTION) == 0 or (input & (IN_UP | IN_DOWN)) != 0:
		return false
	var forward: int = IN_RIGHT if team == 0 else IN_LEFT
	return (input & forward) != 0
```

`_is_active_block()` は接地状態を問わず、この入力と既存のラリー、相手球、ネット距離、進行方向条件を要求する。`_resolve_hit()` から旧 `_is_block_input(p,input)` による無条件skipを削除し、`_is_active_block()` が真の候補だけを通常打球から除外する。条件不成立の前入力は `_classify_intent()` のトスへ流す。

- [ ] **Step 4: 全件を実行して緑を確認する**

Run: `./run_tests.ps1`

Expected: 失敗0、スクリプトエラー0。旧ブロック入力を固定していたテストは新契約へ更新済みである。固定ハッシュ変化が出た場合は新旧値と最初の分岐を報告し、ユーザー承認まで値を更新しない。

- [ ] **Step 5: コミットする**

```powershell
git add -- src/sim/hit_resolver.gd tests/unit/test_controls_original.gd tests/unit/test_hit.gd tests/unit/test_refactor_characterization.gd
git commit -m "feat: ブロックを前入力へ移して地上対応する"
```

---

### Task 3: 空中トスを自陣後方・自陣前方・敵陣の3方向へ揃える

**Files:**
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_hit.gd`
- Modify: `tests/unit/test_return_over_net.gd`
- Modify: `src/sim/hit_resolver.gd`

**Interfaces:**
- Consumes: `toss_target_x(team, hdir, cfg)`, `opponent_return_vx(...)`, intent配列の `hdir`
- Produces: 1・2打目の空中トス3方向と、3打目の方向非依存敵陣返球。

- [ ] **Step 1: 空中トス3方向の失敗テストを書く**

両チームについて、後入力は `toss_zone_back_px`、方向なしは `toss_zone_front_px` を狙い、前入力は相手コートへ到達する検査へ置き換える。3打目は後・なし・前の全入力が同じ安全返球式になることを固定する。

```gdscript
for row in [[backward, own_back], [0, own_front]]:
	HitResolver._apply_hit(s, actor, cfg, SimInput.IN_ACTION | row[0], 0)
	check_eq(HitResolver.trajectory_x_at_y(
		start_x, start_y, s.ball_vx, s.ball_vy, cfg.floor_y, cfg), row[1],
		"1・2打目の空中トス目標")
```

- [ ] **Step 2: 全件を実行して赤を確認する**

Run: `./run_tests.ps1`

Expected: 現実装が全横入力を自陣前方へ送るため、後と前の検査が失敗する。

- [ ] **Step 3: 空中トスの横入力を打球へ配線する**

空中トス分岐の返球条件を次へ変更する。

```gdscript
var returns_to_opponent: bool = serve_strike \
	or touches_after >= cfg.max_touches or hdir == dir
```

返球でない場合は `toss_target_x(team, hdir, cfg)` を使用する。これにより後だけ自陣後方、なしは自陣前方となり、前と3打目は既存の安全な敵陣返球式を使う。

- [ ] **Step 4: 全件を実行して緑を確認する**

Run: `./run_tests.ps1`

Expected: 失敗0、スクリプトエラー0。地上トス、標準トス680、空中縦初速470は変化しない。固定ハッシュ変化が出た場合は空中トス方向の意図した差か対象外回帰かを分けて報告し、ユーザー承認まで値を更新しない。

- [ ] **Step 5: コミットする**

```powershell
git add -- src/sim/hit_resolver.gd tests/unit/test_controls_original.gd tests/unit/test_hit.gd tests/unit/test_return_over_net.gd
git commit -m "feat: 空中トスを自陣二方向と敵陣へ打ち分ける"
```

---

### Task 4: CPUをゲージ別上下アタックと前ブロックへ揃える

**Files:**
- Modify: `tests/unit/test_controls_original.gd`
- Modify: `tests/unit/test_cpu.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`
- Modify: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: `p.drive_gauge`, `p.burnout_ticks`, `cfg.drive_gauge_stock`, `_pick_air_shot(...)`, `_decide_block(...)`
- Produces: `_cpu_attack_vertical(p, cfg) -> int`。余裕ありは `IN_DOWN`、不足またはバーンアウトは `IN_UP`。

- [ ] **Step 1: CPU入力の失敗テストを書く**

```gdscript
check_eq(SimCpu._cpu_attack_vertical(p, cfg), SimInput.IN_DOWN,
	"1本以上ならジャストを狙う")
p.drive_gauge = cfg.drive_gauge_stock - 1
check_eq(SimCpu._cpu_attack_vertical(p, cfg), SimInput.IN_UP,
	"1本未満なら通常アタック")
p.drive_gauge = cfg.drive_gauge_max
p.burnout_ticks = 1
check_eq(SimCpu._cpu_attack_vertical(p, cfg), SimInput.IN_UP,
	"バーンアウト中は通常アタック")
```

空中ブロッカーがチーム相対の前+ボタンを返し、上入力を含まないことを両チームで検査する。接地中のブロッカーは既存どおりジャンプ入力を出し、空中へ入った後だけ前+ボタンを出す。

- [ ] **Step 2: 全件を実行して赤を確認する**

Run: `./run_tests.ps1`

Expected: helper未定義、旧空中ブロックが上+ボタン、攻撃候補が常に下であるため失敗する。

- [ ] **Step 3: CPUの共通入力選択を実装する**

```gdscript
static func _cpu_attack_vertical(p, cfg) -> int:
	if p.burnout_ticks > 0 or p.drive_gauge < cfg.drive_gauge_stock:
		return SimInput.IN_UP
	return SimInput.IN_DOWN
```

`_pick_air_shot()` の3候補へこの縦入力を使う。`_decide_block()` は接地中のジャンプ判断を維持し、空中でブロックするときだけ `IN_ACTION | forward` を返す。試行物理は候補入力をそのまま `preview_air_spike_velocity()` へ渡す。

- [ ] **Step 4: 全件を実行してゴールデン警報を判定する**

Run: `./run_tests.ps1`

Expected: 機能テストは失敗0。同期ゴールデンまたは第2ゴールデンが変わった場合は、新旧ハッシュ、最初に分岐したtick、CPU入力差を報告して停止する。値の更新はユーザー承認後だけ行う。

- [ ] **Step 5: 承認後に意図したゴールデンだけを一度更新して再検証する**

固定値の更新が承認された場合だけ、失敗出力の実測値を対応するテスト定数へ反映し、`./run_tests.ps1` を再実行する。対象外の固定配列や物理値が変化した場合は実装を修正し、ゴールデンで吸収しない。

- [ ] **Step 6: コミットする**

```powershell
git add -- src/sim/sim_cpu.gd tests/unit/test_controls_original.gd tests/unit/test_cpu.gd tests/unit/test_cpu_trial_shot.gd tests/unit/test_sync.gd tests/unit/test_refactor_characterization.gd
git commit -m "feat: CPUを新しいアタックとブロック入力へ揃える"
```

`tests/unit/test_sync.gd` と `tests/unit/test_refactor_characterization.gd` の固定値は、承認済みゴールデン変更が実際に発生した場合だけstageする。

---

### Task 5: ブロック成功を地上・空中で同じ姿勢へ表示する

**Files:**
- Modify: `tests/unit/test_anim_select.gd`
- Modify: `tests/unit/test_sprite_factory.gd`
- Modify: `src/sim/sim_state.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/display/anim_select.gd`
- Modify: `src/display/sprite_factory.gd`

**Interfaces:**
- Consumes: 直列化済みの `Player.hit_kind`
- Produces: `SimStateScript.HIT_KIND_BLOCK=3` と表示アニメ名 `block`。新しい直列化フィールドは追加しない。

- [ ] **Step 1: ブロック姿勢の失敗テストを書く**

`test_anim_select.gd` へ、接地・空中の両方で `hit_kind=HIT_KIND_BLOCK` かつ `hit_cooldown>0` が `block` を返す検査を追加する。`test_sprite_factory.gd` は `block` が `ANIMATIONS` と `FALLBACK` に存在し、原作ビルダーが専用アニメを持つことを検査する。

```gdscript
for on_ground in [0, 1]:
	var p = _player(on_ground, 0, 5)
	p.hit_kind = SimState.HIT_KIND_BLOCK
	check_eq(AnimSelect.anim_for(p), "block", "地上・空中共通ブロック姿勢")
```

- [ ] **Step 2: 全件を実行して赤を確認する**

Run: `./run_tests.ps1`

Expected: `HIT_KIND_BLOCK` と `block` アニメが存在しないため新テストが失敗する。

- [ ] **Step 3: 既存状態と原作セル9で表示を実装する**

`sim_state.gd` に `HIT_KIND_RECEIVE=0`、`HIT_KIND_TOSS=1`、`HIT_KIND_FORWARD=2`、`HIT_KIND_BLOCK=3` を定義し、既存の数値代入と表示比較を定数へ置き換える。ブロック成功時に `p.hit_kind=HIT_KIND_BLOCK` を設定する。

`anim_select.gd` は被弾・横っ飛び・固有動作の後、`hit_cooldown>0 && hit_kind==HIT_KIND_BLOCK` を地上判定より先に評価する。`sprite_factory.gd` は次を追加する。

```gdscript
"block": ["ground_swing", "attack", "idle"],
```

原作シートは `block` へセル9を1コマ登録する。これは `vb22-full.asm` の0x5F64〜0x5F7Eでstate 0x11がキャラクター基準セル+9を選ぶ一次解析結果に合わせる。新画像は作らない。

- [ ] **Step 4: 全件を実行して緑を確認する**

Run: `./run_tests.ps1`

Expected: 失敗0、スクリプトエラー0。新しい直列化フィールドはなく、直列化配列長は変化しない。ブロック成功時の既存 `hit_kind` 値が3へ変わるため、固定ハッシュ変化が出た場合は新旧値と最初のブロック成立tickを報告し、ユーザー承認まで値を更新しない。

- [ ] **Step 5: コミットする**

```powershell
git add -- src/sim/sim_state.gd src/sim/hit_resolver.gd src/display/anim_select.gd src/display/sprite_factory.gd tests/unit/test_anim_select.gd tests/unit/test_sprite_factory.gd
git commit -m "feat: 地上と空中のブロック姿勢を表示する"
```

---

### Task 6: 最終検証と完了記録を固定する

**Files:**
- Modify: `docs/gameplay-controls.md`
- Modify: `docs/tasks/70.md`
- Modify: `docs/remaining-tasks.md`
- Modify: `docs/superpowers/specs/2026-07-25-controls-original-restoration-design.md`

**Interfaces:**
- Consumes: Tasks 1〜5のコミット、全件テスト結果、承認済みゴールデン差分
- Produces: #70の完了記録と次タスクが参照できる実装済み正本

- [ ] **Step 1: 正規入口を新規実行する**

Run: `./run_tests.ps1`

Expected: 全件失敗0、`SCRIPT ERROR summary: 0 occurrence(s)`、同期ゴールデンと性能門を通過する。

- [ ] **Step 2: 仕様の全合格条件を実測確認する**

次をテスト名とコード差分へ対応付ける。

- 上+ボタンは芯でも通常、下+ボタンだけが芯でジャスト。
- 上と下の非ジャスト速度・角度・着弾が3方向で一致。
- 前+ボタンは地上・空中でブロックし、条件外では敵陣トス。
- 空中トスは自陣後方、自陣前方、敵陣の3方向で左右鏡像。
- 3打目は全横入力で敵陣返球。
- CPUはゲージ別上下と前ブロックを使用。
- 地上・空中ブロックは同じ `block` 姿勢を使用。
- ドライブ、ガード、レシーブ、必殺技、能力値の対象外契約に差分がない。

- [ ] **Step 3: 行数、SHA-256、変更全件を完了文書へ記録する**

`docs/tasks/70.md` へ実装コミット、変更ファイル、テスト件数、性能門、ゴールデン差分の有無、未検証の人間試遊を記録する。`docs/gameplay-controls.md` 7節と詳細設計Statusを実装済みへ変更し、`docs/remaining-tasks.md` の#70を完了表示へ変える。

- [ ] **Step 4: 文書差分を検証する**

```powershell
git diff --check
Get-FileHash -Algorithm SHA256 docs/gameplay-controls.md
Get-FileHash -Algorithm SHA256 docs/superpowers/specs/2026-07-25-controls-original-restoration-design.md
Get-FileHash -Algorithm SHA256 docs/tasks/70.md
```

Expected: `git diff --check` は出力なし。3文書の行数とSHA-256を完了報告へ転記できる。

- [ ] **Step 5: Claude Codeへ実装後レビューを依頼する**

依頼内容は、仕様逸脱、上下非ジャスト物理の不一致、ブロック条件外の前トス欠落、CPU入力の旧契約残存、表示状態のロールバック不整合を優先する。指摘はコードと独立テストで確認し、正しいものだけ反映する。

- [ ] **Step 6: レビュー反映後に正規入口を再実行する**

Run: `./run_tests.ps1`

Expected: 全件失敗0、スクリプトエラー0。レビュー後に変更がなければStep 1の結果ではなく、この新規実行結果を最終証拠にする。

- [ ] **Step 7: 完了文書をコミットする**

```powershell
git add -- docs/gameplay-controls.md docs/tasks/70.md docs/remaining-tasks.md docs/superpowers/specs/2026-07-25-controls-original-restoration-design.md
git commit -m "docs: #70の実装結果を記録する"
```

---

## Plan Self-Review

- Spec coverage: 操作9マス、上下ジャスト選択、ブロック衝突、空中トス3方向、3打目、CPU、表示、検証、完了記録をTasks 1〜6へ対応済み。
- Placeholder scan: 未定義の作業指示なし。試遊とゴールデン承認は明示した停止条件であり、暫定実装値ではない。
- Type consistency: intent配列は全タスクで `[kind, hdir, up, allow_just]`、CPU helperは `int`、表示は既存 `hit_kind:int` を使用する。
- Scope: レシーブ三段階、防御経済、能力、CPU戦術#104、押し打ち/離し打ち#76は変更対象外。
