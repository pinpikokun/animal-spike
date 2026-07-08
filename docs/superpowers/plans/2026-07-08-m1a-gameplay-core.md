# M1a ゲームプレイ核 (ネット・ヒット・ラリー・得点・切替・CPU相方) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** シミュレーション層にバレーボールのゲームプレイ(ネット、バンプ/スパイク、サーブ、得点、キャラ切替、CPU相方)を実装し、ヘッドレステストで全て検証する。見た目(素材・UI・CRT)は次のM1bプランで扱う。

**Architecture:** M0の決定論シミュレーション層を拡張する。公開APIを「チーム単位入力」の `tick(state, team_inputs, cfg)` とし、内部で人間入力を操作キャラへ、CPU入力を相方へルーティングして従来の `step()` に流す。CPUロジックもシミュレーション層内(決定論)。ラリー進行はSimState上のフェーズ機械(SERVE/RALLY/POINT_PAUSE)。

**Tech Stack:** Godot 4.6 / GDScript (M0と同じ)

## Global Constraints

- M0の全制約を引き継ぐ: sim層float禁止(静的スキャンが強制)、16.16固定小数点、preload方式、ASCIIコメントの.ps1、テストは `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"` で実行
- 新しい調整値は全て `data/rules.json` に整数で追加する
- SimStateにフィールドを足したら `to_int_array()` にも足す(test_state_coverage.gdが強制する)
- 物理・ルールを変えたら `tests/unit/test_sync.gd` の `GOLDEN_FINAL_HASH` を意図的に更新する(手順は各タスクに明記)
- チーム定義: プレイヤー0,1=左チーム(team 0)、2,3=右チーム(team 1)。チームのindex 0(プレイヤー0と2)が後衛=サーバー
- 入力ビット: IN_LEFT=1, IN_RIGHT=2, IN_JUMP=4, IN_ACTION=8, IN_SWITCH=16
- コミットメッセージは日本語+ `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## ファイル構成

- Modify: `data/rules.json` (ネット・ヒット・サーブ・進行の調整値)
- Modify: `src/sim/sim_config.gd` (新キー読み込み)
- Modify: `src/sim/sim_state.gd` (フェーズ・スコア・タッチ・操作キャラ・クールダウン)
- Create: `src/sim/sim_input.gd` (入力ビット定数の正本。simulation.gdとsim_cpu.gdの両方から参照され、preload循環を防ぐ葉ファイル)
- Modify: `src/sim/simulation.gd` (ネット衝突、ヒット、ラリー進行、tick API)
- Create: `src/sim/sim_cpu.gd` (CPU相方の入力生成、決定論。simulation.gdをpreloadしない)
- Modify: `src/display/main.gd` (デバッグ表示にネット・スコア・フェーズ)
- Create: `tests/unit/test_net.gd`, `tests/unit/test_hit.gd`, `tests/unit/test_rally.gd`, `tests/unit/test_switch.gd`, `tests/unit/test_cpu.gd`
- Modify: `tests/unit/test_config.gd`, `tests/unit/test_state.gd`, `tests/unit/test_sync.gd`

---

### Task 1: ルール調整値の追加

**Files:**
- Modify: `data/rules.json`
- Modify: `src/sim/sim_config.gd`
- Test: `tests/unit/test_config.gd`

**Interfaces:**
- Consumes: M0の `_int_of` / `FP`
- Produces: SimConfigの新フィールド(全てint)。fp単位: `net_x` `net_top_y` `net_half_w` `player_reach` `serve_hold_height`。fp/tick単位: `bump_up_speed` `bump_fwd_speed` `spike_vx` `spike_vy` `serve_vx` `serve_vy`。tick数: `hit_cooldown_ticks` `point_pause_ticks` `serve_delay_ticks`。個数: `max_touches`。px単位のスポーン位置: `spawn_back_px` `spawn_front_px` (これはpx整数のまま持ち、使用側でFP.from_intする)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_config.gd` の末尾に追記:

```gdscript
func test_m1a_keys_loaded() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.net_x, FP.from_int(320), "net_x")
	check_eq(cfg.max_touches, 3, "max_touches")
	check(cfg.spike_vx > 0, "spike_vxが正")
	check(cfg.serve_vy > 0, "serve_vy(上向き量)が正")
	check(cfg.hit_cooldown_ticks > 0, "hit_cooldownが正")
	check_eq(cfg.spawn_back_px, 80, "spawn_back_px")
```

実行して FAIL を確認:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

- [ ] **Step 2: rules.json に追記**

`data/rules.json` を以下の全文で置き換える:

```json
{
	"tick_rate": 60,
	"court_width_px": 640,
	"court_height_px": 360,
	"floor_y_px": 320,
	"gravity_px_s2": 1400,
	"move_speed_px_s": 180,
	"jump_speed_px_s": 430,
	"ball_radius_px": 8,
	"ball_bounce_pct": 78,
	"points_to_win": 15,
	"deuce": 1,
	"net_x_px": 320,
	"net_top_y_px": 240,
	"net_half_w_px": 3,
	"player_reach_px": 22,
	"serve_hold_height_px": 40,
	"bump_up_speed_px_s": 380,
	"bump_fwd_speed_px_s": 120,
	"spike_vx_px_s": 480,
	"spike_vy_px_s": 300,
	"serve_vx_px_s": 260,
	"serve_vy_px_s": 330,
	"hit_cooldown_ticks": 20,
	"point_pause_ticks": 90,
	"serve_delay_ticks": 60,
	"max_touches": 3,
	"spawn_back_px": 80,
	"spawn_front_px": 250
}
```

- [ ] **Step 3: sim_config.gd に読み込みを追加**

`src/sim/sim_config.gd` のフィールド宣言部(`var deuce: bool` の後)に追記:

```gdscript
var net_x: int
var net_top_y: int
var net_half_w: int
var player_reach: int
var serve_hold_height: int
var bump_up_speed: int
var bump_fwd_speed: int
var spike_vx: int
var spike_vy: int
var serve_vx: int
var serve_vy: int
var hit_cooldown_ticks: int
var point_pause_ticks: int
var serve_delay_ticks: int
var max_touches: int
var spawn_back_px: int
var spawn_front_px: int
```

`_init` の `deuce = _int_of(raw, "deuce") != 0` の後に追記:

```gdscript
	net_x = FP.from_int(_int_of(raw, "net_x_px"))
	net_top_y = FP.from_int(_int_of(raw, "net_top_y_px"))
	net_half_w = FP.from_int(_int_of(raw, "net_half_w_px"))
	player_reach = FP.from_int(_int_of(raw, "player_reach_px"))
	serve_hold_height = FP.from_int(_int_of(raw, "serve_hold_height_px"))
	bump_up_speed = FP.from_int(_int_of(raw, "bump_up_speed_px_s")) / tick_rate
	bump_fwd_speed = FP.from_int(_int_of(raw, "bump_fwd_speed_px_s")) / tick_rate
	spike_vx = FP.from_int(_int_of(raw, "spike_vx_px_s")) / tick_rate
	spike_vy = FP.from_int(_int_of(raw, "spike_vy_px_s")) / tick_rate
	serve_vx = FP.from_int(_int_of(raw, "serve_vx_px_s")) / tick_rate
	serve_vy = FP.from_int(_int_of(raw, "serve_vy_px_s")) / tick_rate
	hit_cooldown_ticks = _int_of(raw, "hit_cooldown_ticks")
	point_pause_ticks = _int_of(raw, "point_pause_ticks")
	serve_delay_ticks = _int_of(raw, "serve_delay_ticks")
	max_touches = _int_of(raw, "max_touches")
	spawn_back_px = _int_of(raw, "spawn_back_px")
	spawn_front_px = _int_of(raw, "spawn_front_px")
```

注意: `tests/fixtures/bad_rules.json` にも同じキーを追記すること(gravity_px_s2は1400.5のまま)。キー欠損の連鎖エラーを避けるため。

- [ ] **Step 4: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add data/rules.json src/sim/sim_config.gd tests/unit/test_config.gd tests/fixtures/bad_rules.json
git -C "C:\work\git\Animal Spike" commit -m "M1a: ゲームプレイ調整値をルールに追加"
```

(コミット末尾のCo-Authored-By行は Global Constraints の通り)

---

### Task 2: SimState拡張 (フェーズ・スコア・操作キャラ)

**Files:**
- Modify: `src/sim/sim_state.gd`
- Test: `tests/unit/test_state.gd`

**Interfaces:**
- Consumes: なし
- Produces: SimState新フィールド(全int): `phase` (0=SERVE 1=RALLY 2=POINT_PAUSE 3=GAME_OVER)、`serving_team` (0/1)、`score_l` `score_r`、`touches`、`last_touch_team` (-1/0/1)、`timer` (汎用カウントダウン)、`controlled_l` `controlled_r` (0/1、チーム内の操作キャラindex)、`switch_latch_l` `switch_latch_r` (SWITCHエッジ検出用0/1)、`winner` (-1/0/1)。Player新フィールド: `hit_cooldown`。定数 `PHASE_SERVE:=0` `PHASE_RALLY:=1` `PHASE_POINT_PAUSE:=2` `PHASE_GAME_OVER:=3`。シリアライズ長は25→38 (state 9+ player 1x4 追加)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_state.gd` の `test_serialize_length` を置き換え:

```gdscript
func test_serialize_length() -> void:
	# tick(1) + フェーズ系(12) + プレイヤー4体x6 + ボール4 = 41
	check_eq(SimState.new().to_int_array().size(), 41, "シリアライズ長")
```

実行して FAIL を確認 (expected=41 actual=25)。

- [ ] **Step 2: sim_state.gd を拡張**

`src/sim/sim_state.gd` を以下の全文で置き換える:

```gdscript
# シミュレーションの全状態。全フィールドint(fp)。float禁止
# フィールドを増やしたら必ずto_int_arrayにも足すこと(test_state_coverageが強制する)
extends RefCounted

const PLAYER_COUNT := 4

const PHASE_SERVE := 0
const PHASE_RALLY := 1
const PHASE_POINT_PAUSE := 2
const PHASE_GAME_OVER := 3

class Player:
	var x: int = 0
	var y: int = 0
	var vx: int = 0
	var vy: int = 0
	var on_ground: int = 1
	var hit_cooldown: int = 0

var tick: int = 0
var players: Array[Player] = []
var ball_x: int = 0
var ball_y: int = 0
var ball_vx: int = 0
var ball_vy: int = 0
var phase: int = PHASE_SERVE
var serving_team: int = 0
var score_l: int = 0
var score_r: int = 0
var touches: int = 0
var last_touch_team: int = -1
var timer: int = 0
var controlled_l: int = 0
var controlled_r: int = 0
var switch_latch_l: int = 0
var switch_latch_r: int = 0
var winner: int = -1

func _init() -> void:
	for i in PLAYER_COUNT:
		players.append(Player.new())

func to_int_array() -> Array[int]:
	var out: Array[int] = [tick]
	for p in players:
		out.append(p.x)
		out.append(p.y)
		out.append(p.vx)
		out.append(p.vy)
		out.append(p.on_ground)
		out.append(p.hit_cooldown)
	out.append(ball_x)
	out.append(ball_y)
	out.append(ball_vx)
	out.append(ball_vy)
	out.append(phase)
	out.append(serving_team)
	out.append(score_l)
	out.append(score_r)
	out.append(touches)
	out.append(last_touch_team)
	out.append(timer)
	out.append(controlled_l)
	out.append(controlled_r)
	out.append(switch_latch_l)
	out.append(switch_latch_r)
	out.append(winner)
	return out

func state_hash() -> int:
	# FNV-1a 64bit。オフセット値はint64符号付き表現
	# GDScriptのint64はオーバーフロー時にラップするのでそのまま使える
	var h := -3750763034362895579
	for v in to_int_array():
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h
```

- [ ] **Step 3: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: test_state系とtest_state_coverage(リフレクション)が全PASS。test_syncのGOLDEN一致もこの時点では変わらない(物理は未変更、ハッシュ対象が増えるので**FAILする**)。GOLDENのFAILが出た場合はこのタスクでは想定通り。次のStepで更新する。

- [ ] **Step 4: ゴールデンハッシュを更新**

FAIL表示の `actual=` の値を `tests/unit/test_sync.gd` の `GOLDEN_FINAL_HASH` に転記して再実行、全PASSを確認。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/sim_state.gd tests/unit/test_state.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: SimStateにフェーズ・スコア・操作キャラを追加"
```

---

### Task 3: ネット (プレイヤーのサイド制限とボール反射)

**Files:**
- Modify: `src/sim/simulation.gd`
- Test: `tests/unit/test_net.gd`

**Interfaces:**
- Consumes: SimConfigの `net_x` `net_top_y` `net_half_w`
- Produces: `_step_player(p, input, cfg, team)` がチームに応じてxをサイド内にクランプ(team引数が増える)。`_step_ball` がネット下部(ball_y > net_top_y)でボールを水平反射。ネット越え(net_xをまたぐ)で `touches=0`。ヘルパー `team_of(i: int) -> int` (i/2) と `_dir_of_team(team: int) -> int` (0なら+1、1なら-1) を静的関数で公開

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_net.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _new_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.ball_y = FP.from_int(100)
	s.ball_x = FP.from_int(100)
	return [s, cfg]

func test_left_player_cannot_cross_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = cfg.net_x - FP.from_int(30)
	for i in 120:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x < cfg.net_x, "左チームはネットを越えられない")

func test_right_player_cannot_cross_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[2].x = cfg.net_x + FP.from_int(30)
	for i in 120:
		Simulation.step(s, [0, 0, Simulation.IN_LEFT, 0], cfg)
	check(s.players[2].x > cfg.net_x, "右チームはネットを越えられない")

func test_ball_bounces_off_net_below_top() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.net_x - FP.from_int(12)
	s.ball_y = cfg.net_top_y + FP.from_int(40)
	s.ball_vx = FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "ネット下部で反射する")
	check(s.ball_x < cfg.net_x, "左側に留まる")

func test_ball_passes_above_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.touches = 2
	s.last_touch_team = 0
	s.ball_x = cfg.net_x - FP.from_int(6)
	s.ball_y = cfg.net_top_y - FP.from_int(40)
	s.ball_vx = FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_x > cfg.net_x, "ネット上空は通過する")
	check_eq(s.touches, 0, "ネット越えでタッチ数リセット")
```

実行して FAIL を確認。

- [ ] **Step 2: simulation.gd を拡張**

`src/sim/simulation.gd` の `step` と `_step_player` を置き換え、ヘルパーを追加:

```gdscript
static func team_of(i: int) -> int:
	return i / 2

static func _dir_of_team(team: int) -> int:
	return 1 if team == 0 else -1

static func step(state, inputs: Array[int], cfg) -> void:
	state.tick += 1
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg, team_of(i))
	_step_ball(state, cfg)

static func _step_player(p, input: int, cfg, team: int) -> void:
	p.vx = 0
	if input & IN_LEFT:
		p.vx = -cfg.move_speed
	if input & IN_RIGHT:
		p.vx = cfg.move_speed
	if (input & IN_JUMP) and p.on_ground == 1:
		p.vy = -cfg.jump_speed
		p.on_ground = 0
	if p.on_ground == 0:
		p.vy += cfg.gravity
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w
	else:
		min_x = cfg.net_x + cfg.net_half_w
	p.x = clampi(p.x + p.vx, min_x, max_x)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1
```

`_step_ball` の先頭(`s.ball_vy += cfg.gravity` の前)に越網判定用の変数を、壁反射の後にネット処理を追加。`_step_ball` 全体を以下に置き換え:

```gdscript
static func _step_ball(s, cfg) -> void:
	var prev_x: int = s.ball_x
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	if s.ball_x < left:
		s.ball_x = left + (left - s.ball_x)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif s.ball_x > right:
		s.ball_x = right - (s.ball_x - right)
		s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	if s.ball_y > floor_limit:
		s.ball_y = floor_limit - (s.ball_y - floor_limit)
		s.ball_vy = -s.ball_vy * cfg.ball_bounce_num / cfg.ball_bounce_den
	var ceil_limit: int = cfg.ball_radius
	if s.ball_y < ceil_limit:
		s.ball_y = ceil_limit + (ceil_limit - s.ball_y)
		s.ball_vy = -s.ball_vy * cfg.ball_bounce_num / cfg.ball_bounce_den
	_ball_vs_net(s, cfg, prev_x)

static func _ball_vs_net(s, cfg, prev_x: int) -> void:
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	var net_right: int = cfg.net_x + cfg.net_half_w + cfg.ball_radius
	var below_top: bool = s.ball_y > cfg.net_top_y
	var was_left: bool = prev_x < cfg.net_x
	var is_left: bool = s.ball_x < cfg.net_x
	if below_top:
		# ネット下部は壁。来た側へ押し返す
		if s.ball_x >= net_left and s.ball_x <= net_right:
			if was_left:
				s.ball_x = net_left - (s.ball_x - net_left)
				if s.ball_vx > 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
			else:
				s.ball_x = net_right + (net_right - s.ball_x)
				if s.ball_vx < 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	elif was_left != is_left:
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット
		s.touches = 0
```

- [ ] **Step 3: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: test_net全PASS。**GOLDENはFAILする**(プレイヤークランプとネットが挙動を変えるため)。`actual=`をGOLDEN_FINAL_HASHへ転記して再実行、全PASS。

注意: 既存の `test_player_stays_in_court` は右端クランプがネットに変わるため期待値の修正が必要。右端検証はプレイヤー2(右チーム)で行うよう書き換える:

```gdscript
func test_player_stays_in_court() -> void:
	# 境界の内側から出発して両端のクランプを検証する(境界から始めると空振りする)
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(50)
	for i in 600:
		Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], cfg)
	check_eq(s.players[0].x, 0, "左端で止まる")
	s.players[2].x = cfg.court_width - FP.from_int(50)
	for i in 600:
		Simulation.step(s, [0, 0, Simulation.IN_RIGHT, 0], cfg)
	check_eq(s.players[2].x, cfg.court_width, "右端で止まる")
```

- [ ] **Step 4: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/simulation.gd tests/unit/test_net.gd tests/unit/test_simulation.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: ネット(サイド制限とボール反射、越網タッチリセット)"
```

---

### Task 4: ヒット (バンプとスパイク)

**Files:**
- Modify: `src/sim/simulation.gd`
- Test: `tests/unit/test_hit.gd`

**Interfaces:**
- Consumes: SimConfigの `player_reach` `bump_up_speed` `bump_fwd_speed` `spike_vx` `spike_vy` `hit_cooldown_ticks` `max_touches`
- Produces: `IN_ACTION := 8` 定数。`step()` 内でプレイヤーごとに `_try_hit(state, i, input, cfg)` を呼ぶ。仕様: RALLY中、ACTIONを押していて、ボールとの距離がplayer_reach以内で、hit_cooldown==0のとき発動。接地中=バンプ(ball_vy=-bump_up_speed, ball_vx=チーム方向xbump_fwd_speed)、空中=スパイク(ball_vy=+spike_vy, ball_vx=チーム方向xspike_vx)。発動後hit_cooldown=hit_cooldown_ticks。タッチ数: 同チーム連続なら+1、チーム交代なら1。max_touches超過は即相手の得点(_award_pointはTask 5で実装するため、このタスクでは超過フラグまで。得点処理はTask 5で接続)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_hit.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(250)
	s.players[2].x = FP.from_int(540)
	s.players[3].x = FP.from_int(390)
	return [s, cfg]

func test_bump_on_ground() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(3)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "バンプでボールが上昇する")
	check(s.ball_vx > 0, "左チームのバンプは右向き成分")
	check_eq(s.touches, 1, "タッチ数1")
	check_eq(s.last_touch_team, 0, "最終タッチは左チーム")
	check(s.players[0].hit_cooldown > 0, "クールダウン開始")

func test_no_hit_out_of_reach() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + cfg.player_reach * 3
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "届かなければヒットしない")

func test_spike_in_air() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "スパイクは下向き")
	check(s.ball_vx > 0, "左チームのスパイクは右向き")
	check(s.ball_vx >= cfg.spike_vx, "スパイクは速い")

func test_cooldown_blocks_double_hit() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "1回目でタッチ1")
	# ボールを引き戻して連打
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "クールダウン中は再ヒットしない")

func test_touch_count_resets_on_team_change() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.touches = 2
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "チームが替わればタッチ数は1から")
```

実行して FAIL を確認。

- [ ] **Step 2: 入力定数の正本 sim_input.gd を作り、simulation.gd にヒットを実装**

`src/sim/sim_input.gd` (新規。依存ゼロの葉ファイル。sim_cpu.gdとの循環preloadを防ぐ):

```gdscript
# 入力ビット定数の正本。シミュレーション層の複数ファイルから参照される
extends RefCounted

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_JUMP := 4
const IN_ACTION := 8
const IN_SWITCH := 16
```

`src/sim/simulation.gd` の定数定義を置き換え(既存のIN_LEFT/IN_RIGHT/IN_JUMPの3行を消し、正本参照にする。外部から見た `Simulation.IN_LEFT` 等の名前は変わらない):

```gdscript
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_JUMP := SimInput.IN_JUMP
const IN_ACTION := SimInput.IN_ACTION
const IN_SWITCH := SimInput.IN_SWITCH
```

`step()` を置き換え(ヒット呼び出しを追加):

```gdscript
static func step(state, inputs: Array[int], cfg) -> void:
	state.tick += 1
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg, team_of(i))
		_try_hit(state, i, input, cfg)
	_step_ball(state, cfg)
```

ヒット処理を追加:

```gdscript
static func _try_hit(s, i: int, input: int, cfg) -> void:
	if s.phase != s.PHASE_RALLY:
		return
	if not (input & IN_ACTION):
		return
	var p = s.players[i]
	if p.hit_cooldown > 0:
		return
	var dx: int = s.ball_x - p.x
	var dy: int = s.ball_y - p.y
	var reach: int = cfg.player_reach
	# 両辺ともfp生値の積((fp)^2単位)で比較しスケールを揃える。
	# オーバーフロー検討: dx最大640<<16≈4.2e7、二乗≈1.8e15 < int64上限9.2e18で安全
	if dx * dx + dy * dy > reach * reach:
		return
	var team: int = team_of(i)
	var dir: int = _dir_of_team(team)
	if p.on_ground == 1:
		s.ball_vy = -cfg.bump_up_speed
		s.ball_vx = dir * cfg.bump_fwd_speed
	else:
		s.ball_vy = cfg.spike_vy
		s.ball_vx = dir * cfg.spike_vx
	p.hit_cooldown = cfg.hit_cooldown_ticks
	if s.last_touch_team == team:
		s.touches += 1
	else:
		s.touches = 1
	s.last_touch_team = team
```

注意: `_try_hit` 先頭のフェーズ判定は `if s.phase != SimStateScript.PHASE_RALLY:` と書く(SimStateScriptはStep 2で追加済みのpreload)。

- [ ] **Step 3: テストが通ることを確認 + GOLDEN更新**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

SyncTestの入力は`rng & 7`でACTIONビットを含まないためGOLDENは変わらないはずだが、FAILしたら`actual=`を転記して更新。全PASSを確認。

- [ ] **Step 4: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/simulation.gd tests/unit/test_hit.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: バンプとスパイク(リーチ・クールダウン・タッチ数)"
```

---

### Task 5: ラリー進行 (サーブ・得点・デュース・勝敗)

**Files:**
- Modify: `src/sim/simulation.gd`
- Test: `tests/unit/test_rally.gd`

**Interfaces:**
- Consumes: Task 1-4の全て。SimConfigの `serve_vx` `serve_vy` `serve_hold_height` `point_pause_ticks` `serve_delay_ticks` `points_to_win` `deuce` `spawn_back_px` `spawn_front_px`
- Produces: フェーズ機械。`reset_rally(state, cfg, serving_team)` 静的関数(配置リセット+SERVE開始、初期化にも使う)。SERVE中: ボールはサーバー(serving_teamの後衛=players[team*2])の頭上に固定、サーバーのACTIONで発射(vx=チーム方向xserve_vx、vy=-serve_vy)、RALLYへ。RALLY中: ボールが床に触れたら落ちた側の相手に得点。タッチ超過(touches>max_touches)は相手に得点。得点処理 `_award_point(state, team, cfg)`: スコア加算、勝敗判定(points_to_win到達かつdeuceなら2点差)、勝者未定ならPOINT_PAUSE(timer=point_pause_ticks)、勝者確定ならGAME_OVER。POINT_PAUSE中: timer減算、0でreset_rally(得点チームのサーブ)。床バウンドによる反射はRALLY中の得点判定に置き換わる(床に着いた瞬間に得点、反射しない)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_rally.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _serve_world(serving: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, serving)
	return [s, cfg]

func test_reset_positions() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	check_eq(s.phase, SimState.PHASE_SERVE, "SERVEフェーズ")
	check_eq(s.players[0].x, FP.from_int(cfg.spawn_back_px), "左後衛の位置")
	check_eq(s.players[2].x, cfg.court_width - FP.from_int(cfg.spawn_back_px), "右後衛の位置")
	check_eq(s.touches, 0, "タッチ0")

func test_ball_held_by_server() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 10:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_x, s.players[0].x, "ボールはサーバー頭上に固定(x)")
	check_eq(s.ball_y, s.players[0].y - cfg.serve_hold_height, "ボールはサーバー頭上に固定(y)")

func test_serve_launches_ball() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_RALLY, "サーブでRALLYへ")
	check(s.ball_vx > 0, "左サーブは右向き")
	check(s.ball_vy < 0, "サーブは上向き成分")

func test_floor_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "左コートに落ちたら右チームの得点")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "得点後はポーズ")

func test_pause_then_new_serve_by_scorer() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	for i in cfg.point_pause_ticks + 1:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_SERVE, "ポーズ後は次のサーブ")
	check_eq(s.serving_team, 1, "得点チームがサーブ")

func test_touch_over_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches
	s.last_touch_team = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "4タッチ目で相手の得点")

func test_win_at_15() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_r = cfg.points_to_win - 1
	s.score_l = 5
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.winner, 1, "15点で右チームの勝ち")
	check_eq(s.phase, SimState.PHASE_GAME_OVER, "ゲーム終了フェーズ")

func test_deuce_requires_two_point_lead() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_l = cfg.points_to_win - 1
	s.score_r = cfg.points_to_win - 1
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_l, cfg.points_to_win, "左が15点")
	check_eq(s.winner, -1, "14-15はデュースで未決着")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "続行")
```

実行して FAIL を確認。

- [ ] **Step 2: simulation.gd にラリー進行を実装**

`step()` を最終形に置き換え:

```gdscript
static func step(state, inputs: Array[int], cfg) -> void:
	# matchの定数パターンは識別子束縛の罠があるためif/elifで書く
	state.tick += 1
	if state.phase == SimStateScript.PHASE_SERVE:
		state.timer -= 1
		_step_players_and_hits(state, inputs, cfg)
		_hold_ball_on_server(state, cfg)
		_try_serve(state, inputs, cfg)
	elif state.phase == SimStateScript.PHASE_RALLY:
		_step_players_and_hits(state, inputs, cfg)
		_step_ball(state, cfg)
		_check_floor_point(state, cfg)
	elif state.phase == SimStateScript.PHASE_POINT_PAUSE:
		state.timer -= 1
		if state.timer <= 0:
			reset_rally(state, cfg, state.serving_team)
	# PHASE_GAME_OVERは何もしない

static func _step_players_and_hits(state, inputs: Array[int], cfg) -> void:
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg, team_of(i))
		_try_hit(state, i, input, cfg)
```

サーブとリセットと得点を追加:

```gdscript
static func reset_rally(s, cfg, serving_team: int) -> void:
	s.phase = SimStateScript.PHASE_SERVE
	s.serving_team = serving_team
	s.touches = 0
	s.last_touch_team = -1
	s.timer = cfg.serve_delay_ticks
	var back: int = FP.from_int(cfg.spawn_back_px)
	var front: int = FP.from_int(cfg.spawn_front_px)
	var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
	for i in s.players.size():
		var p = s.players[i]
		p.x = positions[i]
		p.y = cfg.floor_y
		p.vx = 0
		p.vy = 0
		p.on_ground = 1
		p.hit_cooldown = 0
	s.ball_vx = 0
	s.ball_vy = 0
	_hold_ball_on_server(s, cfg)

static func _server_index(s) -> int:
	return s.serving_team * 2

static func _hold_ball_on_server(s, cfg) -> void:
	var server = s.players[_server_index(s)]
	s.ball_x = server.x
	s.ball_y = server.y - cfg.serve_hold_height

static func _try_serve(s, inputs: Array[int], cfg) -> void:
	var idx: int = _server_index(s)
	var input: int = inputs[idx] if idx < inputs.size() else 0
	if not (input & IN_ACTION):
		return
	var dir: int = _dir_of_team(s.serving_team)
	s.ball_vx = dir * cfg.serve_vx
	s.ball_vy = -cfg.serve_vy
	s.touches = 0
	s.last_touch_team = s.serving_team
	s.phase = SimStateScript.PHASE_RALLY

static func _check_floor_point(s, cfg) -> void:
	if s.ball_y < cfg.floor_y - cfg.ball_radius:
		return
	var landed_left: bool = s.ball_x < cfg.net_x
	_award_point(s, 1 if landed_left else 0, cfg)

static func _award_point(s, team: int, cfg) -> void:
	if team == 0:
		s.score_l += 1
	else:
		s.score_r += 1
	s.serving_team = team
	var lead: int = s.score_l - s.score_r if team == 0 else s.score_r - s.score_l
	var score: int = s.score_l if team == 0 else s.score_r
	var won: bool = score >= cfg.points_to_win and (not cfg.deuce or lead >= 2)
	if won:
		s.winner = team
		s.phase = SimStateScript.PHASE_GAME_OVER
	else:
		s.phase = SimStateScript.PHASE_POINT_PAUSE
		s.timer = cfg.point_pause_ticks
```

`_try_hit` のタッチ超過を得点に接続。`_try_hit` の末尾(`s.last_touch_team = team` の後)に追加:

```gdscript
	if s.touches > cfg.max_touches:
		_award_point(s, 1 - team, cfg)
```

床の反射は得点に置き換わるため、`_step_ball` から床反射ブロック(floor_limitの3行)を削除する(RALLYの床接触は_check_floor_pointが処理する)。天井・左右壁・ネットの反射は残す。

**既存テストの追随(このタスク内で必ず行う):**

1. `tests/unit/test_simulation.gd` の `test_ball_floor_bounce_decays` を削除する(仕様変更: 床=得点)
2. 同ファイルのボール系テスト(`test_ball_wall_bounce` `test_ball_right_wall_bounce` `test_ball_ceiling_bounce`)は、フェーズ機械導入後はRALLYでしかボール物理が回らないため、各テストの先頭(`var w := _new_world()` の直後)に `w[0].phase = SimState.PHASE_RALLY` を追加する。いずれも1stepのみで床に触れないため得点判定の影響はない
3. プレイヤー系テスト(移動・ジャンプ・クランプ)はSERVEフェーズ(SimState既定値)のままでよい。SERVE中もプレイヤー物理は動き、ボールはサーバー頭上に固定されるため床得点で試合が進んでしまう事故がない(意図的な設計)
4. `tests/unit/test_net.gd` のボール系2テストも同様に `s.phase = SimState.PHASE_RALLY` を確認(_new_worldで設定済みならそのまま)
5. `tests/unit/test_sync.gd` の `_run_once` はreset_rallyから始まるゲーム全体を回す形にTask 8で更新する。このタスクの時点ではGOLDENのFAILが出たら `actual=` を転記して更新する

- [ ] **Step 3: テスト実行 + GOLDEN更新 + 全PASS確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

- [ ] **Step 4: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/simulation.gd tests/unit/test_rally.gd tests/unit/test_simulation.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: ラリー進行(サーブ・得点・デュース・勝敗)"
```

---

### Task 6: チーム入力API (tick) と操作キャラ切替

**Files:**
- Modify: `src/sim/simulation.gd`
- Modify: `src/display/main.gd`
- Test: `tests/unit/test_switch.gd`

**Interfaces:**
- Consumes: Task 5まで + `sim_cpu.gd` はTask 7(このタスクではCPU=入力なし0で仮結線)
- Produces: 公開API `tick(state, team_inputs: Array[int], cfg) -> void`。team_inputs[0]=左チームの人間入力、[1]=右チームの人間入力。人間入力はそのチームの操作キャラ(`controlled_l/r`)へ届き、相方はCPU入力(Task 7まで暫定0)。IN_SWITCHの立ち上がりエッジ(switch_latch_l/rで検出)で操作キャラをトグル。既存の `step()` はそのまま残る(テスト・内部用)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_switch.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, 0)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(600)
	s.ball_y = FP.from_int(50)
	return [s, cfg]

func test_human_input_reaches_controlled_char() -> void:
	var w := _world()
	var s = w[0]
	var x0: int = s.players[0].x
	var x1: int = s.players[1].x
	for i in 30:
		Simulation.tick(s, [Simulation.IN_RIGHT, 0], w[1])
	check(s.players[0].x > x0, "操作キャラ(index0)が動く")
	check_eq(s.players[1].x, x1, "相方は人間入力では動かない(CPU未実装なので静止)")

func test_switch_toggles_on_edge() -> void:
	var w := _world()
	var s = w[0]
	check_eq(s.controlled_l, 0, "初期操作キャラは0")
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 1, "SWITCH押下で切替")
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 1, "押しっぱなしでは再切替しない(エッジ検出)")
	Simulation.tick(s, [0, 0], w[1])
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 0, "離して押し直すと戻る")

func test_after_switch_input_reaches_new_char() -> void:
	var w := _world()
	var s = w[0]
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	var x1: int = s.players[1].x
	for i in 30:
		Simulation.tick(s, [Simulation.IN_RIGHT, 0], w[1])
	check(s.players[1].x > x1, "切替後はindex1が動く")
```

実行して FAIL を確認。

- [ ] **Step 2: tick APIを実装**

`src/sim/simulation.gd` に追加:

```gdscript
# 公開API: チーム単位入力(人間2系統)から各プレイヤー入力を組み立てて1tick進める
# CPU相方の入力はsim_cpu.gdが決定論的に生成する
static func tick(state, team_inputs: Array[int], cfg) -> void:
	var in_l: int = team_inputs[0] if team_inputs.size() > 0 else 0
	var in_r: int = team_inputs[1] if team_inputs.size() > 1 else 0
	_handle_switch(state, in_l, in_r)
	var per_player: Array[int] = [0, 0, 0, 0]
	for team in 2:
		var human: int = in_l if team == 0 else in_r
		var controlled: int = state.controlled_l if team == 0 else state.controlled_r
		for slot in 2:
			var idx: int = team * 2 + slot
			if slot == controlled:
				per_player[idx] = human & ~IN_SWITCH
			else:
				per_player[idx] = _cpu_input(state, idx, cfg)
	step(state, per_player, cfg)

static func _handle_switch(state, in_l: int, in_r: int) -> void:
	var press_l: int = 1 if (in_l & IN_SWITCH) else 0
	if press_l == 1 and state.switch_latch_l == 0:
		state.controlled_l = 1 - state.controlled_l
	state.switch_latch_l = press_l
	var press_r: int = 1 if (in_r & IN_SWITCH) else 0
	if press_r == 1 and state.switch_latch_r == 0:
		state.controlled_r = 1 - state.controlled_r
	state.switch_latch_r = press_r

static func _cpu_input(_state, _idx: int, _cfg) -> int:
	# Task 7でsim_cpu.gdに委譲する。暫定は入力なし
	return 0
```

- [ ] **Step 3: main.gd をtick APIに切り替え**

`src/display/main.gd` の `_physics_process` の `Simulation.step(state, [input, 0, 0, 0], cfg)` を次に置き換え:

```gdscript
	Simulation.tick(state, [input, 0], cfg)
```

さらにキー割当にACTIONとSWITCHを追加(`input |= Simulation.IN_JUMP` の行の後):

```gdscript
	if Input.is_key_pressed(KEY_X):
		input |= Simulation.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= Simulation.IN_SWITCH
```

また `_ready` の初期配置ブロック(players[0..3].xとball設定、計6行)を削除して次の1行に置き換え:

```gdscript
	Simulation.reset_rally(state, cfg, 0)
```

- [ ] **Step 4: テスト実行 + GOLDEN更新(必要時) + 全PASS確認 + Commit**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
git -C "C:\work\git\Animal Spike" add src/sim/simulation.gd src/display/main.gd tests/unit/test_switch.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: チーム入力APIと操作キャラ切替(エッジ検出)"
```

---

### Task 7: CPU相方 v0

**Files:**
- Create: `src/sim/sim_cpu.gd`
- Modify: `src/sim/simulation.gd`
- Test: `tests/unit/test_cpu.gd`

**Interfaces:**
- Consumes: SimState/SimConfig/Simulationの定数
- Produces: `sim_cpu.gd` の静的関数 `decide(state, idx: int, cfg) -> int` (入力ビットを返す、完全決定論)。v0仕様: (1)自分がサーバーでSERVE中: timer<=0になったらACTION(人間がサーバーのときはtickの人間入力が優先される設計のため、CPUサーバーのみ自動サーブ)。(2)RALLY中でボールが自陣側: ボールのx方向へ移動(不感帯reach/2)、リーチ内でACTION。(3)それ以外: スポーン位置へ戻る。simulation.gdの `_cpu_input` を `SimCpu.decide` への委譲に置き換える

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_cpu.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, 0)
	return [s, cfg]

func test_cpu_chases_ball_on_own_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(100)
	# players[1](左チーム相方、spawn_front=250)から見てボールは左
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "ボールへ向かって左移動")

func test_cpu_hits_in_reach() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x + FP.from_int(3)
	s.ball_y = s.players[1].y - FP.from_int(10)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION, "リーチ内でACTION")

func test_cpu_ignores_ball_on_other_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ACTION), "敵陣のボールは打たない")

func test_cpu_auto_serves() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左チームのサーバーはplayers[0]。人間が相方(index1)を操作している想定で
	# tick経由でCPUサーバーの自動サーブを検証する
	s.controlled_l = 1
	var served := false
	for i in cfg.serve_delay_ticks + 10:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUサーバーが自動サーブする")

func test_cpu_returns_to_spawn() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = FP.from_int(100)
	s.players[1].x = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "持ち場(spawn_front=250)へ戻る")
```

実行して FAIL を確認。

- [ ] **Step 2: sim_cpu.gd を実装**

`src/sim/sim_cpu.gd` (新規):

```gdscript
# CPU相方の入力生成。シミュレーション層の一部なので完全決定論・int演算のみ
# 状態を読むだけで書き換えない(副作用禁止)。v0: ボール追跡と単純ヒット
# simulation.gdをpreloadしない(循環防止)。定数はsim_input.gdから取る
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")

static func decide(s, idx: int, cfg) -> int:
	var team: int = idx / 2
	var p = s.players[idx]
	if s.phase == SimStateScript.PHASE_SERVE:
		# サーブ遅延タイマーはsimulation.gdのstep()が減算する(ここは読むだけ)
		if idx == s.serving_team * 2 and s.timer <= 0:
			return SimInput.IN_ACTION
		return 0
	if s.phase != SimStateScript.PHASE_RALLY:
		return 0
	var on_own_side: bool = (s.ball_x < cfg.net_x) == (team == 0)
	var target_x: int
	if on_own_side:
		target_x = s.ball_x
	else:
		var back: int = FP.from_int(cfg.spawn_back_px)
		var front: int = FP.from_int(cfg.spawn_front_px)
		var positions: Array[int] = [back, front, cfg.court_width - back, cfg.court_width - front]
		target_x = positions[idx]
	var input := 0
	var deadzone: int = cfg.player_reach / 2
	if p.x < target_x - deadzone:
		input |= SimInput.IN_RIGHT
	elif p.x > target_x + deadzone:
		input |= SimInput.IN_LEFT
	if on_own_side:
		var dx: int = s.ball_x - p.x
		var dy: int = s.ball_y - p.y
		if dx * dx + dy * dy <= cfg.player_reach * cfg.player_reach:
			input |= SimInput.IN_ACTION
	return input
```

- [ ] **Step 3: simulation.gd の_cpu_inputを委譲に変更**

simulation.gd先頭のpreload群に追加:

```gdscript
const SimCpu := preload("res://src/sim/sim_cpu.gd")
```

`_cpu_input` を置き換え:

```gdscript
static func _cpu_input(state, idx: int, cfg) -> int:
	return SimCpu.decide(state, idx, cfg)
```

依存方向の確認: simulation.gd→sim_cpu.gd→(fp, sim_input, sim_state)で一方向。sim_cpu.gdはsimulation.gdをpreloadしないため循環はない。

- [ ] **Step 4: テスト実行 + GOLDEN更新 + 全PASS確認 + Commit**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
git -C "C:\work\git\Animal Spike" add src/sim/sim_cpu.gd src/sim/simulation.gd tests/unit/test_cpu.gd tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: CPU相方v0(ボール追跡・自動サーブ)"
```

---

### Task 8: SyncTest強化とデバッグ表示の更新

**Files:**
- Modify: `tests/unit/test_sync.gd`
- Modify: `src/display/main.gd`

**Interfaces:**
- Consumes: 全タスクの成果
- Produces: SyncTestがtick API(チーム入力2系統、全ビット0-31)でゲーム全体(サーブ→ラリー→得点→再サーブ)を回す形になる。デバッグ表示にネット・スコア・フェーズが出る

- [ ] **Step 1: SyncTestをtick APIに更新**

`tests/unit/test_sync.gd` の `_run_once` を置き換え:

```gdscript
func _run_once() -> Array[int]:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, 0)
	var hashes: Array[int] = []
	var rng := 123456789
	for t in TICKS:
		var inputs: Array[int] = []
		for i in 2:
			rng = _next_rand(rng)
			inputs.append(rng & 31)
		Simulation.tick(s, inputs, cfg)
		if t % 60 == 0:
			hashes.append(s.state_hash())
	hashes.append(s.state_hash())
	return hashes
```

実行 → GOLDEN不一致のFAILが出るので `actual=` を転記して更新 → 全PASS。

- [ ] **Step 2: デバッグ表示を更新**

`src/display/main.gd` の `_draw` を置き換え:

```gdscript
func _draw() -> void:
	var fy := float(FP.to_int(cfg.floor_y))
	draw_line(Vector2(0, fy), Vector2(640, fy), Color(0.4, 0.4, 0.55))
	var nx := float(FP.to_int(cfg.net_x))
	var nty := float(FP.to_int(cfg.net_top_y))
	draw_line(Vector2(nx, nty), Vector2(nx, fy), Color(0.6, 0.6, 0.7))
	for i in state.players.size():
		var p = state.players[i]
		var team := Simulation.team_of(i)
		var color := Color(0.9, 0.8, 0.3) if team == 0 else Color(0.4, 0.8, 0.9)
		var controlled: int = state.controlled_l if team == 0 else state.controlled_r
		if i % 2 == controlled:
			color = color.lightened(0.3)
		draw_circle(Vector2(FP.to_int(p.x), FP.to_int(p.y)), 6.0, color)
	draw_circle(
		Vector2(FP.to_int(state.ball_x), FP.to_int(state.ball_y)),
		float(FP.to_int(cfg.ball_radius)), Color(0.95, 0.95, 0.95))
```

`_physics_process` のlabel.textを置き換え:

```gdscript
	label.text = "SIM DEBUG VIEW (開発用計器)\n%d - %d  phase=%d touches=%d\ntick=%d\n矢印:移動 Z:ジャンプ X:アクション C:交代" % [
		state.score_l, state.score_r, state.phase, state.touches, state.tick]
```

- [ ] **Step 3: ヘッドレス起動確認 + 全テスト + Commit**

```powershell
& "C:\work\git\Animal Spike\tools\godot\Godot_v4.6-stable_win64_console.exe" --headless --path "C:\work\git\Animal Spike" --quit-after 180
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
git -C "C:\work\git\Animal Spike" add tests/unit/test_sync.gd src/display/main.gd
git -C "C:\work\git\Animal Spike" commit -m "M1a: SyncTestのフルゲーム化とデバッグ表示更新"
git -C "C:\work\git\Animal Spike" tag m1a
```

---

## M1aのスコープ外 (次のプラン)

- M1b: フリー素材の組み込み(キャラアニメ・ボール・背景)、スコアUI、CRTフィルター、表示オプション、ユーザーの官能チェック
- 追加要望(スタン・ダッシュ・ジャストレシーブ)の採否判断素材はM1bの手触り確認と同時に提示
- ローカル2人対戦の入力2系統割当(キーボード分割/パッド)はM1bで表示と合わせて結線(tick APIは既に2系統対応)
