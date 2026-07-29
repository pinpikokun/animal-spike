# CPU Jump Trigger AND Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ラリー攻撃ジャンプを、現在球の横距離80px・横速度10px/tick・縦速度5px/tick・高さ215pxの厳密AND条件で発火させる。

**Architecture:** `SimCpu._jump_ball_ok(s, p)` が固定小数の4境界を一箇所で判定し、ラリー攻撃ジャンプの入口だけを閉じる。条件外では精密経路の離陸だけでなく芯位置取りも止め、通常の落下点追随へ戻す。会合予測、役割代行、サーブ、ブロックは既存責務を維持し、各tickで条件を外れた精密計画は保持しない。

**Tech Stack:** Godot 4.6 / GDScript / 16.16固定小数点 / PowerShell / `run_tests.ps1`

## Global Constraints

- 実装元は `docs/superpowers/specs/2026-07-29-cpu-jump-trigger-and-gate-design.md` 122行、SHA-256 `ae1fded7b91d715863547caa5f04f58763c6696436d51d011202c29ff635e791`。
- 4条件は `abs(dx) < FP.from_int(80)`、`abs(vx) < FP.from_int(10)`、`abs(vy) < FP.from_int(5)`、`ball_y < FP.from_int(215)` の厳密AND。
- 対象はラリー中の地上攻撃ジャンプだけ。サーブ、ブロック、空中打撃へ適用しない。
- `_jump_will_meet()` と `_sweet_jump_plan()`、`PlayerMovement`、役割代行の責務を変更しない。
- 精密計画は毎tick再判定し、条件外へ出たら保持しない。永続状態、ヒステリシス、乱数を追加しない。
- 製品コードより先に失敗テストを書き、REDとGREENを正規入口 `run_tests.ps1` で確認する。
- 固定値または同期ハッシュが変わった場合は原因を切り分け、Claude Codeへ査読を依頼する。

---

### Task 1: 承認版固定と導入前実測

**Files:**
- Read: `docs/superpowers/specs/2026-07-29-cpu-jump-trigger-and-gate-design.md`
- Create temporarily: `tests/zz_jump_gate_measure.gd`
- Do not commit: `tests/zz_jump_gate_measure.gd`

**Interfaces:**
- Consumes: `Simulation.step(state, inputs, cfg)`、`SimCpu.decide(state, idx, cfg)`
- Produces: 導入前の16試合について、攻撃ジャンプ数、得点推移、ラリーtick合計

- [ ] **Step 1: 設計書の同一性を検証する**

Run:

```powershell
$p = 'docs/superpowers/specs/2026-07-29-cpu-jump-trigger-and-gate-design.md'
(Get-Content -Encoding utf8 $p).Count
(Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
```

Expected: `122` と `ae1fded7b91d715863547caa5f04f58763c6696436d51d011202c29ff635e791`。

- [ ] **Step 2: 使い捨て測定を作る**

`tests/zz_jump_gate_measure.gd`:

```gdscript
extends SceneTree

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const Chars := preload("res://src/sim/chars.gd")

func _initialize() -> void:
	var result := {"attack_jumps": 0, "points": 0, "rally_ticks": 0, "scores": []}
	for match_idx in 16:
		var cfg = SimConfig.new()
		var s = SimState.new()
		Simulation.reset_match(s, cfg, match_idx % 2, Chars.ROSTER,
			0x1234 + match_idx * 7919, match_idx * 31)
		for p in s.players:
			p.cpu = SimCpu.PRESET_MAX
		var match_rally_ticks := 0
		for tick_idx in 4000:
			s.rng = SimRng.advance_frame(s.rng, s.aitick)
			var inputs: Array[int] = []
			for idx in 4:
				inputs.append(SimCpu.decide(s, idx, cfg))
				var team: int = idx / 2
				if s.phase == SimState.PHASE_RALLY and s.players[idx].on_ground == 1 \
						and (inputs[idx] & Simulation.IN_JUMP) \
						and s.last_touch_team == team \
						and s.ball_attack_kind == SimState.BALL_ATTACK_NONE \
						and s.serve_flight == 0:
					result.attack_jumps += 1
			var before_score: int = s.score_l + s.score_r
			if s.phase == SimState.PHASE_RALLY:
				match_rally_ticks += 1
			Simulation.step(s, inputs, cfg)
			if s.score_l + s.score_r > before_score:
				result.points += 1
		result.rally_ticks += match_rally_ticks
		result.scores.append("%d-%d" % [s.score_l, s.score_r])
	print("JUMP_GATE_MEASURE ", JSON.stringify(result))
	quit()
```

- [ ] **Step 3: 導入前値を採取する**

Run:

```powershell
& 'tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script res://tests/zz_jump_gate_measure.gd
```

Expected: `JUMP_GATE_MEASURE` が1行出る。16試合はサーブ側、`rng_word`、`aitick_word` が
異なり、同一走行の水増しにならない。出力を作業記録へ控え、スクリプトは実装後の
同条件測定まで残す。帽子・超必経路の同条件ジャンプも含み得るため、`attack_jumps` は
ラリー攻撃ジャンプの上界として比較する。

### Task 2: 固定小数のAND判定

**Files:**
- Modify: `tests/unit/test_cpu.gd`
- Modify: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: 状態の `ball_x`、`ball_y`、`ball_vx`、`ball_vy` とプレイヤーの `x`
- Produces: `static func _jump_ball_ok(s, p) -> bool`

- [ ] **Step 1: 境界の失敗テストを書く**

`tests/unit/test_cpu.gd` へ追加:

```gdscript
func test_jump_ball_gate_uses_strict_fixed_point_boundaries() -> void:
	var w := _world()
	var s = w[0]
	var p = s.players[1]
	s.ball_x = p.x + FP.from_int(80) - 1
	s.ball_vx = FP.from_int(10) - 1
	s.ball_vy = -FP.from_int(5) + 1
	s.ball_y = FP.from_int(215) - 1
	check(SimCpu._jump_ball_ok(s, p), "4条件の境界直前は合格")
	s.ball_x = p.x + FP.from_int(80)
	check(not SimCpu._jump_ball_ok(s, p), "横距離80pxは不合格")
	s.ball_x = p.x - FP.from_int(80)
	check(not SimCpu._jump_ball_ok(s, p), "横距離-80pxは不合格")
	s.ball_x = p.x
	s.ball_vx = FP.from_int(10)
	check(not SimCpu._jump_ball_ok(s, p), "横速度+10px/tickは不合格")
	s.ball_vx = -FP.from_int(10)
	check(not SimCpu._jump_ball_ok(s, p), "横速度-10px/tickは不合格")
	s.ball_vx = 0
	s.ball_vy = FP.from_int(5)
	check(not SimCpu._jump_ball_ok(s, p), "縦速度+5px/tickは不合格")
	s.ball_vy = -FP.from_int(5)
	check(not SimCpu._jump_ball_ok(s, p), "縦速度-5px/tickは不合格")
	s.ball_vy = 0
	s.ball_y = FP.from_int(215)
	check(not SimCpu._jump_ball_ok(s, p), "高さ215pxは不合格")
```

- [ ] **Step 2: REDを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: `_jump_ball_ok` 未定義を原因としてexit 1。既存検査の期待値変更ではない。

- [ ] **Step 3: 最小実装を入れる**

`src/sim/sim_cpu.gd` の位置取り定数付近:

```gdscript
const JUMP_BALL_MAX_DX_PX := 80
const JUMP_BALL_MAX_VX_PX := 10
const JUMP_BALL_MAX_VY_PX := 5
const JUMP_BALL_MAX_Y_PX := 215

static func _jump_ball_ok(s, p) -> bool:
	return absi(s.ball_x - p.x) < FP.from_int(JUMP_BALL_MAX_DX_PX) \
		and absi(s.ball_vx) < FP.from_int(JUMP_BALL_MAX_VX_PX) \
		and absi(s.ball_vy) < FP.from_int(JUMP_BALL_MAX_VY_PX) \
		and s.ball_y < FP.from_int(JUMP_BALL_MAX_Y_PX)
```

- [ ] **Step 4: GREENを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 新しい境界検査を含め全件成功、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 5: 独立部品をコミットする**

```powershell
git add -- src/sim/sim_cpu.gd tests/unit/test_cpu.gd
git commit -m "test: CPUジャンプ球質ゲートの境界を固定する"
```

### Task 3: ラリー攻撃入口へゲートを接続

**Files:**
- Modify: `tests/unit/test_cpu.gd`
- Modify: `src/sim/sim_cpu.gd`

**Interfaces:**
- Consumes: `SimCpu._jump_ball_ok(s, p) -> bool`
- Produces: 精密経路と通常経路に共通する、現在球AND付きラリー攻撃ジャンプ

- [ ] **Step 1: 判断経路の失敗テストを書く**

`tests/unit/test_cpu.gd` へ、既存 `test_attack_cpu_jumps_to_meet_toss()` と同じ世界を作る
`_attack_jump_world(profile)` を追加する。状態はラリー、左チームの1打目、index 1が
アタッカー役、プレイヤーxはネット左48px、球xは同じ、球yは160px、速度0とする。

```gdscript
func _attack_jump_world(profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.last_touch_idx = 0
	s.touches = 1
	var p = s.players[1]
	p.x = cfg.net_x - FP.from_int(48)
	p.cpu = profile
	s.ball_x = p.x
	s.ball_y = FP.from_int(160)
	s.ball_vx = 0
	s.ball_vy = 0
	_set_rally_role_roll(s, 0, 2)
	return [s, cfg]

func _attack_sweet_r(cfg, p) -> int:
	return cfg.player_reach * cfg.spike_sweet_pct \
		* Chars.stat(p.char_id, "just_window") / (100 * 100)

func test_attack_jump_requires_every_ball_gate_condition() -> void:
	var profile := _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	var w := _attack_jump_world(profile)
	check(SimCpu.decide(w[0], 1, w[1]) & Simulation.IN_JUMP, "条件内では跳ぶ")
	var failures := [
		["横距離", FP.from_int(80), 0, 0, FP.from_int(160)],
		["横速度", 0, FP.from_int(10), 0, FP.from_int(160)],
		["縦速度", 0, 0, FP.from_int(5), FP.from_int(160)],
		["高さ", 0, 0, 0, FP.from_int(215)],
	]
	for failure in failures:
		w = _attack_jump_world(profile)
		var s = w[0]
		var p = s.players[1]
		s.ball_x = p.x + failure[1]
		s.ball_vx = failure[2]
		s.ball_vy = failure[3]
		s.ball_y = failure[4]
		check_eq(SimCpu.decide(s, 1, w[1]) & Simulation.IN_JUMP, 0,
			failure[0] + "違反では跳ばない")
```

- [ ] **Step 2: 精密待機の中止と再合格を検査する**

```gdscript
func test_sweet_jump_wait_rechecks_gate_each_tick() -> void:
	var profile := _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK | SimCpu.AB_SWEET,
		0, 0, 0, 255, 3, 3)
	var w := _attack_jump_world(profile)
	var s = w[0]
	var cfg = w[1]
	var p = s.players[1]
	s.ball_x = p.x + FP.from_int(40)
	var waiting_plan: Array[int] = SimCpu._sweet_jump_plan(
		s, p, cfg, _attack_sweet_r(cfg, p))
	check(waiting_plan[0] > 0, "前提: 合格中は未来の離陸を待つ")
	SimCpu.decide(s, 1, cfg)
	# 次の観測tickを、計画上は即離陸できるが速度条件を外れた状態にする。
	s.ball_x = p.x
	s.ball_vy = FP.from_int(5)
	check_eq(SimCpu._sweet_jump_plan(s, p, cfg, _attack_sweet_r(cfg, p))[0], 0,
		"前提: ゲート無しなら精密経路は今跳ぶ")
	check_eq(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, 0,
		"離陸tickでも条件外なら計画を保持しない")
	s.ball_vy = 0
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP,
		"再合格時は再計算した計画で跳ぶ")
```

- [ ] **Step 3: 非役持ち代行の回帰検査を書く**

```gdscript
func test_jump_gate_keeps_non_attacker_substitution() -> void:
	var profile := _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	var w := _attack_jump_world(profile)
	var s = w[0]
	var cfg = w[1]
	s.players[0].cpu = profile
	s.players[0].x = s.ball_x
	s.players[1].x = FP.from_int(20)
	check(not SimCpu._is_rally_attacker(s, 0), "前提: index 0は非役持ち")
	check(not SimCpu._jump_will_meet(s, s.players[1], cfg, cfg.player_reach),
		"前提: 役持ちの相方は会合不能")
	check(SimCpu.decide(s, 0, cfg) & Simulation.IN_JUMP,
		"条件内なら非役持ちが代行する")
```

- [ ] **Step 4: REDを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 少なくとも高さ215pxの判断検査と精密待機中止が失敗する。肯定ケースの
「条件内では跳ぶ」「合格中は未来の離陸を待つ」はRED時点から成功し、テスト配置の
誤りを製品実装で直す形になっていない。既存検査は変更しない。

- [ ] **Step 5: ラリー攻撃入口へ一条件だけ追加する**

`src/sim/sim_cpu.gd` のラリー攻撃大if:

```gdscript
	if (ab & AB_ATTACK) and _attack_ok(s, idx, prof) \
			and p.on_ground == 1 and p.stun == 0 and not miss_roll \
			and s.serve_flight == 0 \
			and s.last_touch_team == team and s.touches < cfg.max_touches \
			and attacker_priority and not own_toss_for_human_mate \
			and _jump_ball_ok(s, p):
```

- [ ] **Step 6: GREENを確認する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 新規検査を含め、同期ゴールデン以外は成功する。同期ゴールデンが変わった場合は
値をまだ更新せず、失敗がその1件だけか確認してTask 4へ進む。

- [ ] **Step 7: 挙動本体をコミットする**

同期ゴールデンも含め全件成功した場合だけ、この段階でコミットする。コミットフックも
全件検査を行うため、ゴールデンが赤なら未コミットのままTask 4の原因査読と再採取まで
進み、同一コミットへまとめる。

```powershell
git add -- src/sim/sim_cpu.gd tests/unit/test_cpu.gd
git commit -m "fix: CPUジャンプを原作AND条件へ絞る"
```

### Task 4: 回帰判定、実測、文書完了

**Files:**
- Modify if justified: `tests/unit/test_sync.gd`
- Modify: `docs/tasks/85.md`
- Modify: `docs/remaining-tasks.md`
- Delete: `tests/zz_jump_gate_measure.gd`

**Interfaces:**
- Consumes: Task 1の導入前実測、Task 3の製品挙動
- Produces: 全件検証、導入後比較、#85完了記録

- [ ] **Step 1: 同期ハッシュ差を切り分ける**

`run_tests.ps1` で赤になった検査を全件列挙し、各々についてCPU入力列の変化だけが原因か
切り分ける。CPU経路を通らない手入力駆動の物理特性検査が赤なら、意図外の回帰として
停止する。各ゴールデンの旧値、実測値、他検査の結果、
`SCRIPT ERROR summary: 0 occurrence(s)` をClaude Codeへ提示する。Claude CodeとCodexの
双方が承認済みANDゲートによる意図したCPU入力列変更だけだと合意した場合に限り、
CPU経路由来と確認できたゴールデンを同一根拠、同一コミットでまとめて更新する。
更新した全定数の旧値と新値を作業記録に残す。

- [ ] **Step 2: 導入後値を同じ測定で採取する**

Run:

```powershell
& 'tools/godot/Godot_v4.6-stable_win64_console.exe' --headless --path . --script res://tests/zz_jump_gate_measure.gd
```

導入前後の `attack_jumps`、`points`、`rally_ticks`、16試合の `scores` を比較する。
ジャンプ減少が失点増加またはラリー崩壊へ変わった疑いがあれば、閾値を変えず停止し、
数値をClaude Codeへ再査読させる。

- [ ] **Step 3: 使い捨て測定を削除する**

`tests/zz_jump_gate_measure.gd` を削除する。このパスは `.gitignore` 対象なので、
`Test-Path 'tests/zz_jump_gate_measure.gd'` が `False` を返すことで実在しないことを
直接確認する。

- [ ] **Step 4: 正規入口を全件実行する**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`

Expected: 全件成功、失敗0、`SCRIPT ERROR summary: 0 occurrence(s)`。

- [ ] **Step 5: タスク文書を実測へ合わせる**

`docs/tasks/85.md` の状態を完了へ変え、採用値、実装箇所、RED/GREEN、全件数、同期ハッシュの
扱い、導入前後実測、Claude Codeの最終レビューを記録する。`docs/remaining-tasks.md` は
#85の行を完了表記へ変え、現役の未完了一覧から外す。

- [ ] **Step 6: Claude Codeへ最終コードレビューを依頼する**

提示するもの:

- 承認設計書の行数とSHA-256
- `git diff` 全文
- REDとGREENの出力要約
- 導入前後の固定条件実測
- 同期ハッシュを変えた場合は旧値、新値、他検査の結果

指摘は証拠で検証し、必要な修正後に正規入口を再実行する。

- [ ] **Step 7: 完了をコミットする**

```powershell
git add -- src/sim/sim_cpu.gd tests/unit/test_cpu.gd tests/unit/test_sync.gd docs/tasks/85.md docs/remaining-tasks.md
git commit -m "fix: CPUジャンプ発火条件を原作AND判定へ絞る"
```

コミット対象に存在しない差分は追加しない。コミットフックの全件結果を最終証拠とする。
