# CPU空中打撃の物理整合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CPUの空中打撃予測と実打球を同じ最終速度へ統一し、4政策、空中トス、ネット越し接触を承認済み仕様へ合わせる。

**Architecture:** `HitResolver.preview_air_spike_velocity()` を読み取り専用の速度正本とし、実打球とCPU仮想打球の両方から呼ぶ。`SimCpu` は実入力ごとの最終速度だけを評価し、状態を変更しない派生抽選で30/30/30/10の政策を選ぶ。

**Tech Stack:** Godot 4.6、GDScript、16.16固定小数点、独自ヘッドレステストランナー。

## Global Constraints

- 承認設計は総491行、固定本文482行、SHA-256 `8e470c25877c764d90f74b2f80e9954a599bf699c8f5bba5787ce2ad2f11e9a7`。
- 3方向の速度設定値、打撃楕円、必殺技優先順位、整数演算、決定論を変えない。
- 試し打ちは実球、プレイヤー、ゲージ、`rng`、`aitick`、タッチ状態を変えない。
- `PlayerMovement`、`_jump_will_meet()`、`_sweet_jump_plan()` は変更しない。
- 製品コードより先に失敗テストを書き、正規入口 `run_tests.ps1` でREDとGREENを確認する。

---

### Task 1: 空中打撃の最終速度を一つの正本へ統合

**Files:**
- Modify: `tests/unit/test_hit.gd`
- Modify: `src/sim/hit_resolver.gd`

**Interfaces:**
- Consumes: `HitResolver._classify_intent()`、`Chars.stat()`、`_mura_power_pct()`、既存慣性設定。
- Produces: `static func preview_air_spike_velocity(s, actor: int, cfg, input: int, d2: int) -> Vector2i`。

- [ ] **Step 1: 独立期待値を持つ失敗テストを書く**

`test_hit.gd` に左右チームと3方向を表で検査する。期待値はAPIを使わず、設定値から明示する。

```gdscript
func test_preview_air_spike_velocity_matches_fixed_normal_values() -> void:
	for team in 2:
		for row in [[-1, "steep"], [0, "mid"], [1, "flat"]]:
			var w := _air_spike_world(team)
			var input: int = _air_spike_input(team, row[0])
			var actual: Vector2i = HitResolver.preview_air_spike_velocity(
				w[0], team * 2, w[1], input, w[2])
			var expected: Vector2i = _independent_air_spike_velocity(
				w[0], team * 2, w[1], row[0], false)
			check_eq(actual, expected, "通常3方向の固定期待値")
```

同じ独立式でジャスト、上昇球、下降球、サーブ、攻撃値差、むらっけ、制御喪失を個別テストにする。

- [ ] **Step 2: REDを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: `preview_air_spike_velocity` 未定義により対象テストがFAILし、終了コードが非0。

- [ ] **Step 3: 読み取り専用APIを最小実装する**

`_apply_hit()` と同じ順序で `sweet`、`inertia`、`mangled`、`aim_pct`、`pct`、3方向速度を計算し、状態へ代入せず返す。

```gdscript
static func preview_air_spike_velocity(
		s, actor: int, cfg, input: int, d2: int) -> Vector2i:
	var p = s.players[actor]
	var team: int = team_of(actor)
	var dir: int = SimStateScript._dir_of_team(team)
	var serve_strike: bool = s.phase == SimStateScript.PHASE_SERVE \
		and s.serve_tossed == 1
	var special: int = _special_for_input(p, input, cfg)
	var intent: Array[int] = _classify_intent(
		p.on_ground, input, d2, cfg.player_reach, serve_strike)
	var sweet_r: int = cfg.player_reach * cfg.spike_sweet_pct \
		* Chars.stat(p.char_id, "just_window") / 10000
	var sweet: bool = d2 >= 0 and d2 <= sweet_r * sweet_r
	if special != 0:
		sweet = true
	if p.burnout_ticks > 0:
		sweet = false
	var inertia: int = cfg.hit_inertia_just_num if sweet else cfg.hit_inertia_num
	var in_sp2: int = s.ball_vx * s.ball_vx + s.ball_vy * s.ball_vy
	if in_sp2 < cfg.inertia_min_speed * cfg.inertia_min_speed:
		inertia = 0
	inertia = maxi(inertia * (200 - Chars.stat(p.char_id, "absorb")) / 100, 0)
	if serve_strike:
		inertia = 0
	var incoming_unblockable: bool = s.ball_defense_class == Chars.DEFENSE_UNBLOCKABLE
	var opposing_power: bool = s.last_touch_team >= 0 \
		and s.last_touch_team != team and s.ball_power == 1 \
		and not incoming_unblockable
	var mangled: bool = opposing_power and not sweet
	var aim_pct: int = MANGLE_AIM_PCT if mangled else 100
	if mangled:
		inertia = cfg.hit_inertia_den
	var pct: int = cfg.spike_normal_pct
	if sweet:
		pct = cfg.spike_power_pct * Chars.stat(p.char_id, "just_reward") / 100
	pct = pct * Chars.stat(p.char_id, "atk") / 100
	pct = pct * _mura_power_pct(s, actor, p.char_id) / 100
	var relative_hdir: int = intent[1] * dir
	var sv := Vector2i(dir * cfg.spike_mid_vx * pct / 100,
		(cfg.spike_steep_vy + cfg.spike_vy) * pct / 200)
	if relative_hdir < 0:
		sv = Vector2i(dir * cfg.spike_steep_vx * pct / 100,
			cfg.spike_steep_vy * pct / 100)
	elif relative_hdir > 0:
		sv = Vector2i(dir * cfg.spike_vx * pct / 100,
			cfg.spike_vy * pct / 100)
	return Vector2i(sv.x * aim_pct / 100 - s.ball_vx * inertia / cfg.hit_inertia_den,
		sv.y * aim_pct / 100 - s.ball_vy * inertia / cfg.hit_inertia_den)
```

- [ ] **Step 4: 実打球の速度代入を共通APIへ委譲する**

`_apply_hit()` の状態変更前に戻り値を保持し、既存の演出・ゲージ・攻撃種別処理を残したまま `ball_vx/ball_vy` だけを保持値から代入する。

- [ ] **Step 5: GREENと既存速度回帰を確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 新規速度テスト、既存スパイクテスト、全件がPASS。

- [ ] **Step 6: コミットする**

```powershell
git add src/sim/hit_resolver.gd tests/unit/test_hit.gd
git commit -m "refactor: 空中打撃の最終速度を共通化する"
```

### Task 2: CPU候補と4政策を実打球速度へ切り替える

**Files:**
- Create: `tests/unit/test_cpu_trial_shot.gd`
- Modify: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: `HitResolver.preview_air_spike_velocity()`、`SimRng.derived_value()`、`_land_x_from()`、`_clears_net()`。
- Produces: `SALT_AIR_SHOT := 8` と、actor・`d2` を受け取る `_pick_air_shot()`。

- [ ] **Step 1: 根因と政策の失敗テストを書く**

新規テストに、固定速度なら③奥が有効になる根因フィクスチャと、0..9の剰余を作る固定`aitick`表を置く。

```gdscript
func test_policy_mapping_is_three_three_three_one() -> void:
	for residue in 10:
		var s = _world()[0]
		s.aitick = _aitick_for_residue(residue)
		check_eq(SimCpu._air_shot_policy(s), residue / 3 if residue < 9 else 3,
			"政策写像 " + str(residue))

func test_policy_two_uses_valid_flat_spike_from_real_velocity() -> void:
	var w := _root_cause_world()
	var input: int = SimCpu._pick_air_shot(
		w[0], w[2], w[1], 0, true, w[3])
	check_eq(input, Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		"政策2は実速度で有効な③奥を採用")
```

政策1の先着順、政策3の最遠・同点順、政策甲の即時トス、全候補無効の安全弁、actor・tick・難易度非依存も分けて検査する。

- [ ] **Step 2: REDを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 新規政策APIと新しい `_pick_air_shot()` 契約が未実装のためFAIL。

- [ ] **Step 3: 実入力から3候補を生成する**

①はネット逆方向、②は横なし、③はネット方向を組み、同じactorと`d2`で共通APIを呼ぶ。候補生成から `toss_aim_vx()` と `spike_target_x()` を除く。

- [ ] **Step 4: 有効判定と4政策を実装する**

```gdscript
const SALT_AIR_SHOT := 8

static func _air_shot_policy(s) -> int:
	var roll: int = SimRng.derived_value(s.aitick, 0, SALT_AIR_SHOT) % 10
	return roll / 3 if roll < 9 else 3
```

政策甲は候補生成前に `IN_ACTION` を返す。政策1から3は必要な候補だけを評価し、落下先とネット通過の両方を満たさなければ `IN_ACTION` へ落とす。

- [ ] **Step 5: 難易度分岐と空中入力の混入を除く**

`P_TIQ >= 2` 分岐を撤去し、空中接触時は `_decide_air_hit()` の戻り値で左右・上下・ACTIONを置き換える。上昇中の `IN_JUMP` は既存末尾処理で保持する。

- [ ] **Step 6: GREENを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 根因、政策、難易度共通、既存CPUテストがPASS。

- [ ] **Step 7: コミットする**

```powershell
git add src/sim/sim_cpu.gd tests/unit/test_cpu_trial_shot.gd
git commit -m "feat: CPU空中打撃の四政策を実装する"
```

### Task 3: 空中トスとネット越し接触を承認仕様へ合わせる

**Files:**
- Modify: `tests/unit/test_hit.gd`
- Modify: `tests/unit/test_cpu_trial_shot.gd`
- Modify: `src/sim/hit_resolver.gd`
- Modify: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: `toss_target_x(team, 0, cfg)`、`toss_aim_vx()`、`opponent_return_vx()`。
- Produces: 1・2打目の自陣前方トス、3打目の敵陣返球、ネット通過済み候補の有効化。

- [ ] **Step 1: 空中トスとネット越し接触の失敗テストを書く**

```gdscript
func test_first_and_second_air_toss_target_own_front() -> void:
	for touches in [0, 1]:
		var w := _air_toss_world(0, touches)
		HitResolver._apply_hit(w[0], 0, w[1], Simulation.IN_ACTION, 0)
		var expected_vx: int = HitResolver.toss_aim_vx(
			w[2], w[3], -w[1].toss_fwd_vy,
			HitResolver.toss_target_x(0, 0, w[1]), w[1])
		check_eq(w[0].ball_vx, expected_vx, "1・2打目は自陣前方")

func test_third_air_toss_returns_to_opponent() -> void:
	var w := _air_toss_world(0, 2)
	HitResolver._apply_hit(w[0], 0, w[1], Simulation.IN_ACTION, 0)
	check(SimCpu._predict_landing_x(w[0], w[1],
		w[1].floor_y - w[1].ball_radius, 3) > w[1].net_x,
		"3打目は相手コートへ返る")
```

左右鏡像、政策甲と安全弁の同一入力、ネット相手側かつ楕円内の接触成立、楕円外の不成立を追加する。

- [ ] **Step 2: REDを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 現行空中トスが常に敵陣返球であるため1・2打目テストがFAILし、ネット再通過要求のテストもFAIL。

- [ ] **Step 3: タッチ後回数で空中トスを分ける**

```gdscript
var touches_after: int = s.touches + 1 if s.last_touch_team == team else 1
var returns_to_opponent: bool = touches_after >= cfg.max_touches
```

`returns_to_opponent` が真なら既存敵陣返球、偽なら `-cfg.toss_fwd_vy` と自陣前方目標から `toss_aim_vx()` を使う。

- [ ] **Step 4: ネット通過済み判定を実装する**

打撃開始時の `ball_x` が打ち手から見て相手側なら `_clears_net()` を要求せず、相手コート落下だけを検査する。楕円接触条件は `_resolve_hit()` の既存処理を使う。

- [ ] **Step 5: GREENを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 空中トス、ネット越し接触、全既存テストがPASS。

- [ ] **Step 6: コミットする**

```powershell
git add src/sim/hit_resolver.gd src/sim/sim_cpu.gd tests/unit/test_hit.gd tests/unit/test_cpu_trial_shot.gd
git commit -m "fix: CPU空中トスとネット越し接触を整合させる"
```

### Task 4: 同期回帰と完了検証

**Files:**
- Modify only if required: `tests/unit/test_sync.gd`

**Interfaces:**
- Consumes: 正規入口の全件結果と、変更前後の同期ゴールデン値。
- Produces: 説明可能な同期ハッシュと最終検証記録。

- [ ] **Step 1: 正規入口を実行する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 終了コード0、全テスト0 failed、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 2: 同期ゴールデン差分を判定する**

`test_sync.gd` だけが意図した入力列変更で赤い場合に限り、新旧値、変更到達経路、テスト件数、失敗件数を記録して実測値を更新する。それ以外の固定値変化では停止する。

- [ ] **Step 3: 設計合格条件を機械確認する**

```powershell
rg -n "toss_aim_vx|spike_target_x|P_TIQ.*>= 2" src/sim/sim_cpu.gd
git diff --check
git status --short
```

Expected: アタック候補生成に旧逆算式なし、選択経路に難易度分岐なし、空白エラーなし、変更は設計対象だけ。

- [ ] **Step 4: 最終コミットする**

```powershell
git add tests/unit/test_sync.gd
git commit -m "test: CPU空中打撃の同期ゴールデンを更新する"
```

同期値が変わらなければこのコミットは作らない。
