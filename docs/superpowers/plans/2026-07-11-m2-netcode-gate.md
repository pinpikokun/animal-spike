# M2 ネットコード検証ゲート 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1の成果物をgodot-rollback-netcode+GodotSteamでオンライン化し、「2台実PC・Steam経由・30分デシンクゼロ+ローカル同等の操作感(ユーザー判定)」の合否ゲートを実施可能にする。

**Architecture:** 自前決定論sim(src/sim/)はそのまま、薄皮アダプタで載せる。SyncManagerのrollback対象は「入力ノードL/R(各ピア所有)+SimRoot(状態保存とtick)」の3ノードのみ。ツリー順で入力ノードが先に_network_processで入力を書き込み、最後にSimRootがSimulation.tick()を1回回す。表示は既存game_viewをexternal_simモードで再利用。

**Tech Stack:** Godot 4.6 + godot-rollback-netcode v1.0.0(GitLab本家) + GodotSteam 4.19.1-gde(Codeberg)。フェーズ1はENetで同一PC2プロセス、フェーズ2でSteam(Spacewar appid 480)。

**事前調査資料:** docs/superpowers/research/2026-07-11-m2-netcode-research.md (出典付き。着手前に必読)

## Global Constraints

- sim層(src/sim/)はint64のみ・float禁止(test_no_float_in_sim.gdが検査。小数リテラルも検出する)
- SimStateにフィールドを足したらto_int_array/load_int_arrayの両方に足す(test_state_coverageが強制)
- class_name禁止。参照は全てpreload()
- .ps1ファイルはASCIIコメントのみ(PowerShell 5.1のBOM問題)
- ローカル1人プレイ(root.tscn起動)の挙動を壊さない。ネット対戦は起動引数--netでのみ入る
- テスト実行: `powershell -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1`(必ずtimeout付き、ヘッドレスGodotは居座ることがある)
- コミットはタスクごと。pre-commitフックが全テストを回す
- ゲーム画面にプレースホルダー禁止。ただしネット検証HUD(ping/デシンク計)はSIM DEBUG VIEW同様の開発計器で例外

## 合否ゲートの定義(設計書3.3節より転記)

- 合格: 2台の実PCでSteam経由の実対戦、30分連続でデシンクゼロ、かつ操作感がローカル対戦と区別つかない(判定は100%ユーザー)
- 不合格: Unity+Photon Quantum 3へ移行(協議の上)。設計・素材・調整値は持ち越す
- 補助: Delta Rollbackフォークの可用性を初期に確認(タスク2に含む。アクセス不能なら記録して本家続行)

---

### Task 1: SimStateの復元 load_int_array

**Files:**
- Modify: `src/sim/sim_state.gd`
- Test: `tests/unit/test_state.gd`

**Interfaces:**
- Produces: `SimState.load_int_array(arr: Array) -> void` — to_int_arrayの逆操作。後続タスクのSimRoot._load_state()が使う

- [ ] **Step 1: 失敗するテストを書く** — tests/unit/test_state.gd末尾に追加:

```gdscript
func test_load_int_array_roundtrip() -> void:
	# to_int_array→load_int_arrayの往復で全フィールドが復元される(ロールバックの土台)
	var a = SimState.new()
	a.tick = 123
	a.ball_x = 456789
	a.phase = SimState.PHASE_RALLY
	a.score_l = 7
	a.winner = 1
	a.players[2].x = 999
	a.players[3].hit_cooldown = 5
	var b = SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.state_hash(), a.state_hash(), "往復でハッシュ一致")
	check_eq(b.players[2].x, 999, "プレイヤー座標の復元")
	check_eq(b.tick, 123, "tickの復元")

func test_load_int_array_overwrites_everything() -> void:
	# 汚れた状態に読み込んでも完全に上書きされる(ロールバック時は必ず過去へ戻す)
	var clean = SimState.new()
	var snapshot: Array[int] = clean.to_int_array()
	var dirty = SimState.new()
	dirty.tick = 555
	dirty.ball_vy = -777
	dirty.players[0].on_ground = 0
	dirty.load_int_array(snapshot)
	check_eq(dirty.state_hash(), clean.state_hash(), "汚れが完全に消える")
```

- [ ] **Step 2: 落ちることを確認** — `run_tests.ps1`実行。期待: `load_int_array`が存在せずスクリプトエラー(FAIL扱い)
- [ ] **Step 3: 実装** — sim_state.gdのto_int_arrayの直後に追加。**順序はto_int_arrayと完全一致させること**:

```gdscript
func load_int_array(arr: Array) -> void:
	# to_int_arrayの逆。順序を変えるときは必ず両方同時に変える
	var k := 0
	tick = arr[k]; k += 1
	for p in players:
		p.x = arr[k]; k += 1
		p.y = arr[k]; k += 1
		p.vx = arr[k]; k += 1
		p.vy = arr[k]; k += 1
		p.on_ground = arr[k]; k += 1
		p.hit_cooldown = arr[k]; k += 1
	ball_x = arr[k]; k += 1
	ball_y = arr[k]; k += 1
	ball_vx = arr[k]; k += 1
	ball_vy = arr[k]; k += 1
	phase = arr[k]; k += 1
	serving_team = arr[k]; k += 1
	score_l = arr[k]; k += 1
	score_r = arr[k]; k += 1
	touches = arr[k]; k += 1
	last_touch_team = arr[k]; k += 1
	timer = arr[k]; k += 1
	controlled_l = arr[k]; k += 1
	controlled_r = arr[k]; k += 1
	switch_latch_l = arr[k]; k += 1
	switch_latch_r = arr[k]; k += 1
	winner = arr[k]; k += 1
```

- [ ] **Step 4: 通ることを確認** — `run_tests.ps1`実行。期待: 89テスト全緑
- [ ] **Step 5: コミット** — `git add src/sim/sim_state.gd tests/unit/test_state.gd` → `git commit -m "M2-T1: SimState.load_int_array(ロールバック復元の土台)"`

---

### Task 2: godot-rollback-netcode v1.0.0 導入

**Files:**
- Create: `addons/godot-rollback-netcode/` (GitLab本家v1.0.0からベンダリング)
- Modify: `project.godot` (プラグイン有効化+オートロード)
- Create: `tmp_probe_addon.gd` (使い捨て起動プローブ。確認後削除)

**Interfaces:**
- Produces: オートロード`SyncManager`(以降のタスクが`SyncManager.start()`等を呼ぶ)

- [ ] **Step 1: 取得** — PowerShellで:

```powershell
Invoke-WebRequest -Uri "https://gitlab.com/snopek-games/godot-rollback-netcode/-/archive/v1.0.0/godot-rollback-netcode-v1.0.0.zip" -OutFile "$env:TEMP\rollback.zip"
Expand-Archive "$env:TEMP\rollback.zip" -DestinationPath "$env:TEMP\rollback"
# addons/godot-rollback-netcode だけをリポジトリへコピー
Copy-Item -Recurse "$env:TEMP\rollback\godot-rollback-netcode-v1.0.0\addons\godot-rollback-netcode" "addons\godot-rollback-netcode"
```

- [ ] **Step 2: README精読** — `addons/godot-rollback-netcode/README.md`(またはリポジトリ直下のREADME)のInstallation/Minimal setup節を読み、(a)必要なオートロード名とパス、(b)ノード登録方式(network_syncグループか否か)、(c)ProjectSettingsのキー名(network/rollback/...)を控える。以降のステップのパス・名称はREADME実物を正とする
- [ ] **Step 3: 有効化** — project.godotに追記(READMEで確認した正確なパスを使う。想定):

```ini
[autoload]
SyncManager="*res://addons/godot-rollback-netcode/SyncManager.gd"

[editor_plugins]
enabled=PackedStringArray("res://addons/godot-rollback-netcode/plugin.cfg")
```

- [ ] **Step 4: 起動プローブ** — tmp_probe_addon.gd:

```gdscript
extends SceneTree
func _init() -> void:
	# オートロードはSceneTree直下に乗るまで1フレーム要るためdeferredで見る
	call_deferred("_check")
func _check() -> void:
	var sm = root.get_node_or_null("SyncManager")
	print("SYNC_MANAGER_OK=", sm != null)
	quit()
```

実行(timeout 60秒):
```powershell
tools\godot\Godot_v4.6-stable_win64_console.exe --headless --path . --script res://tmp_probe_addon.gd
```
期待: `SYNC_MANAGER_OK=true`。確認後 `Remove-Item tmp_probe_addon.gd`

- [ ] **Step 5: 全テスト+ローカル起動確認** — run_tests.ps1全緑、かつ `--headless --quit-after 180` でroot.tscnがエラーなく起動終了すること
- [ ] **Step 6: Delta Rollback可用性チェック(タイムボックス15分)** — https://gitlab.com/BimDav/delta_rollback をWebFetchで確認。アクセス可否・Godot 4対応・最終更新だけ記録し、docs/superpowers/research/2026-07-11-m2-netcode-research.mdの5節に追記。**どちらでも本家v1.0.0で続行**(比較評価はフェーズ1ソーク通過後に必要なら)
- [ ] **Step 7: コミット** — `git add addons project.godot docs` → `git commit -m "M2-T2: godot-rollback-netcode v1.0.0導入(GitLab本家)"`

---

### Task 3: 入力ポーリングの共通化 InputPoll

**Files:**
- Create: `src/display/input_poll.gd`
- Modify: `src/display/game_view.gd` (インライン収集を置換)

**Interfaces:**
- Produces: `InputPoll.poll() -> int` (現在のキー状態をsim入力ビットに変換。表示層、Input使用可)
- Consumes: `SimInput`定数(IN_LEFT=1, IN_RIGHT=2, IN_JUMP=4, IN_ACTION=8, IN_SWITCH=16)

- [ ] **Step 1: 実装** — src/display/input_poll.gd(表示層のためテストなし。純ロジックなし):

```gdscript
# キーボード状態をsim入力ビットへ変換する。表示層(Input使用可)
extends RefCounted

const SimInput := preload("res://src/sim/sim_input.gd")

static func poll() -> int:
	var input := 0
	if Input.is_key_pressed(KEY_LEFT):
		input |= SimInput.IN_LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		input |= SimInput.IN_RIGHT
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_SPACE):
		input |= SimInput.IN_JUMP
	if Input.is_key_pressed(KEY_X):
		input |= SimInput.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= SimInput.IN_SWITCH
	return input
```

- [ ] **Step 2: game_view.gdを置換** — preloadに `const InputPoll := preload("res://src/display/input_poll.gd")` を足し、_physics_processのキー収集10行を `var input := InputPoll.poll()` に置換
- [ ] **Step 3: 検証** — run_tests.ps1全緑 + `--quit-after 180`ヘッドレス起動OK + 実機でゲームを起動し矢印/Z/X/Cが全て効くことを確認
- [ ] **Step 4: コミット** — `git commit -m "M2-T3: 入力ポーリングをInputPollへ抽出(ネット対戦と共用)"`

---

### Task 4: SimRootアダプタと入力ノード

**Files:**
- Create: `src/net/net_input_node.gd`
- Create: `src/net/sim_root.gd`
- Test: `tests/unit/test_sim_root.gd`

**Interfaces:**
- Consumes: Task1の`load_int_array`、Task3の`InputPoll.poll()`
- Produces:
  - `NetInputNode`: `var team: int`。`_get_local_input() -> Dictionary`(={"i": int})、`_predict_remote_input(prev, ticks) -> Dictionary`、`_network_process(input)`でSimRootへ`set_team_input(team, input.get("i", 0))`
  - `SimRoot`: `var cfg` `var state` `func set_team_input(team: int, bits: int)` `func _network_process(_input)`(両入力でSimulation.tick 1回) `func _save_state() -> Dictionary` `func _load_state(d)`
- ツリー構成の掟: InputL → InputR → SimRoot の順に配置(SyncManagerはツリー順に_network_processを呼ぶため、SimRootが最後=入力が揃ってからtick)

- [ ] **Step 1: 失敗するテストを書く** — tests/unit/test_sim_root.gd(SyncManager非依存の純ロジックのみ検証):

```gdscript
extends "res://tests/test_case.gd"

const SimRoot := preload("res://src/net/sim_root.gd")
const SimState := preload("res://src/sim/sim_state.gd")

func _make_root():
	var r = SimRoot.new()
	r.setup()  # cfg/state生成+reset_match(表示なし)
	return r

func test_network_process_advances_one_tick() -> void:
	var r = _make_root()
	var t0: int = r.state.tick
	r.set_team_input(0, 0)
	r.set_team_input(1, 0)
	r._network_process({})
	check_eq(r.state.tick, t0 + 1, "1回で1tick進む")
	r.free()

func test_save_load_state_roundtrip() -> void:
	var r = _make_root()
	r._network_process({})
	var saved: Dictionary = r._save_state()
	var h0: int = r.state.state_hash()
	for i in 30:
		r.set_team_input(0, 2)  # 右移動で状態を汚す
		r._network_process({})
	check(r.state.state_hash() != h0, "前提: 状態が進んで変わっている")
	r._load_state(saved)
	check_eq(r.state.state_hash(), h0, "ロールバック復元でハッシュが戻る")
	check_eq(saved["h"], h0, "保存辞書のハッシュキーも一致")
	r.free()

func test_team_inputs_reach_sim() -> void:
	var r = _make_root()
	var x0: int = r.state.players[0].x
	r.set_team_input(0, 2)  # IN_RIGHT
	r.set_team_input(1, 0)
	r._network_process({})
	check(r.state.players[0].x > x0, "左チーム入力が操作キャラに届く")
	r.free()
```

- [ ] **Step 2: 落ちることを確認** — run_tests.ps1。期待: sim_root.gdが無くロードFAIL
- [ ] **Step 3: 実装** — src/net/sim_root.gd:

```gdscript
# ロールバックネットコードと自前決定論simの接続点。
# SyncManagerからは「状態の保存/復元」と「毎tickの_network_process」だけを受け、
# sim本体(src/sim/)には一切手を入れない薄皮アダプタ
extends Node

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

var cfg
var state
var _team_inputs: Array[int] = [0, 0]

func setup() -> void:
	# テストとnet_matchの両方から呼ぶ初期化(表示なし)
	cfg = SimConfig.new()
	state = SimState.new()
	Simulation.reset_match(state, cfg, 0)

func _ready() -> void:
	if cfg == null:
		setup()
	add_to_group("network_sync")

func set_team_input(team: int, bits: int) -> void:
	_team_inputs[team] = bits

func _network_process(_input: Dictionary) -> void:
	Simulation.tick(state, [_team_inputs[0], _team_inputs[1]], cfg)
	_team_inputs = [0, 0]

func _save_state() -> Dictionary:
	# to_int_arrayは毎回新規配列を返すのでアドオンの「複製必須」制約を満たす
	return {"s": state.to_int_array(), "h": state.state_hash()}

func _load_state(d: Dictionary) -> void:
	state.load_int_array(d["s"])
```

src/net/net_input_node.gd:

```gdscript
# 1チーム分の入力担当ノード。所有ピアのマシンでだけ_get_local_inputが呼ばれ、
# 相手側では受信入力/予測入力が_network_processに渡ってくる
extends Node

const InputPoll := preload("res://src/display/input_poll.gd")

var team: int = 0
var sim_root: Node = null

func _ready() -> void:
	add_to_group("network_sync")

func _get_local_input() -> Dictionary:
	return {"i": InputPoll.poll()}

func _predict_remote_input(previous_input: Dictionary, _ticks_since_real_input: int) -> Dictionary:
	# 予測は「最後の入力を押しっぱなし」。格闘/スポーツ系の定石
	return previous_input.duplicate()

func _network_process(input: Dictionary) -> void:
	if sim_root != null:
		sim_root.set_team_input(team, input.get("i", 0))
```

- [ ] **Step 4: 通ることを確認** — run_tests.ps1全緑(92テスト)
- [ ] **Step 5: アドオン整合の確認** — addons/godot-rollback-netcode/README.mdの「Minimal setup」と照合し、(a)network_syncグループ方式で正しいか、(b)_network_processのシグネチャ(引数の型)一致、(c)入力Dictionaryのキー制約(String推奨等)を確認。相違があればこのタスク内で修正しREADME引用をコミットメッセージに残す
- [ ] **Step 6: コミット** — `git commit -m "M2-T4: SimRoot+入力ノード(自前simをrollback対象に載せる薄皮)"`

---

### Task 5: ネット対戦シーン(フェーズ1: ENet同一PC2プロセス)

**Files:**
- Create: `src/net/net_match.gd`, `src/net/net_match.tscn`
- Modify: `src/display/game_view.gd` (external_simモード追加)
- Modify: `src/display/root.gd` (--net引数時にnet_match.tscnをロード)
- Create: `scripts/run_net_test.ps1` (ASCIIコメントのみ)

**Interfaces:**
- Consumes: Task4のSimRoot/NetInputNode、SyncManagerオートロード
- Produces: 起動引数 `--net host` / `--net join [address]`(既定127.0.0.1)。game_view.gdの`external_sim: bool`と`external_state`(SimRootのstateを表示するだけのモード)

- [ ] **Step 1: game_viewにexternal_simモード** — game_view.gdへ追加:

```gdscript
var external_sim := false
var external_state = null

func attach_external(cfg_in, state_ref) -> void:
	external_sim = true
	cfg = cfg_in
	state = state_ref
	external_state = state_ref
```

_physics_processの先頭に:

```gdscript
	if external_sim:
		_sync_sprites()
		$ScoreUI.update_from(state)
		return
```

注意: _readyはcfg/stateを自前生成するため、attach_externalは**instantiate直後・add_child前**に呼び、_ready側は `if external_sim: return を早期に…` とはせず、_readyの`cfg = SimConfig.new()`以下の生成部を `if not external_sim:` で囲む(スプライト生成は両モード共通なので囲まない)。実装時にreadyの構造を確認して分岐を入れること

- [ ] **Step 2: net_match実装** — net_match.tscnはNode2D1個(スクリプトはnet_match.gd)だけのシーン。子ノード(InputL/InputR/SimRoot/GameView/HUD)は全て_readyでコード生成する:

```gdscript
# フェーズ1: ENetで2プロセス対戦する検証シーン。M2ゲートの土台
extends Node2D

const SimRootScript := preload("res://src/net/sim_root.gd")
const NetInputScript := preload("res://src/net/net_input_node.gd")
const GameViewScene := preload("res://src/display/game_view.tscn")

const PORT := 42424

var _sim_root
var _hud: Label
var _mismatch_count := 0
var _started_at_msec := 0

func _ready() -> void:
	_sim_root = SimRootScript.new()
	_sim_root.name = "SimRoot"
	_sim_root.setup()
	var input_l = NetInputScript.new()
	input_l.name = "InputL"
	input_l.team = 0
	input_l.sim_root = _sim_root
	var input_r = NetInputScript.new()
	input_r.name = "InputR"
	input_r.team = 1
	input_r.sim_root = _sim_root
	# ツリー順=処理順。入力2ノードの後にSimRoot(入力が揃ってからtick)
	add_child(input_l)
	add_child(input_r)
	add_child(_sim_root)
	var view := GameViewScene.instantiate()
	view.attach_external(_sim_root.cfg, _sim_root.state)
	add_child(view)
	_hud = Label.new()
	_hud.position = Vector2(4, 4)
	var hud_layer := CanvasLayer.new()
	hud_layer.add_child(_hud)
	add_child(hud_layer)
	_connect_net()

func _connect_net() -> void:
	var args := OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	if args.has("host"):
		peer.create_server(PORT, 1)
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		var address := "127.0.0.1"
		for a in args:
			if a.contains("."):
				address = a
		peer.create_client(address, PORT)
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected_to_server)

func _assign_authorities(host_id: int, client_id: int) -> void:
	$InputL.set_multiplayer_authority(host_id)
	$InputR.set_multiplayer_authority(client_id)
	$SimRoot.set_multiplayer_authority(host_id)

func _on_peer_connected(peer_id: int) -> void:
	_assign_authorities(1, peer_id)
	SyncManager.add_peer(peer_id)
	SyncManager.start()

func _on_connected_to_server() -> void:
	_assign_authorities(1, multiplayer.get_unique_id())
	SyncManager.add_peer(1)
	# startはホスト側のみが呼ぶ(アドオンの流儀。READMEで確認)

func _process(_delta: float) -> void:
	if _started_at_msec == 0 and _sim_root.state.tick > 0:
		_started_at_msec = Time.get_ticks_msec()
	var elapsed := 0
	if _started_at_msec > 0:
		elapsed = (Time.get_ticks_msec() - _started_at_msec) / 1000
	_hud.text = "tick=%d  経過=%d秒  mismatch=%d" % [_sim_root.state.tick, elapsed, _mismatch_count]
```

実装時にアドオンREADMEで確認して追加すること(シグナル名はREADME/SyncManager.gdソースを正とする): `SyncManager.sync_started` `sync_stopped` `sync_error(msg)`、state mismatch通知のシグナル(あれば`_mismatch_count`加算+push_errorで記録)。SyncManagerのProjectSettings(`network/rollback/ticks_per_second`等)がrules.jsonのtick_rate=60と一致することも確認

- [ ] **Step 3: root.gdの分岐** — root.gd._readyの冒頭で `if OS.get_cmdline_user_args().has("host") or OS.get_cmdline_user_args().has("join"):` の場合はgame_view.tscnの代わりにnet_match.tscnをViewportへ載せる(既存のF1切替・メニューはそのまま)
- [ ] **Step 4: 起動スクリプト** — scripts/run_net_test.ps1(ASCIIコメントのみ):

```powershell
# Launch two windowed instances on one PC for phase-1 net test.
$godot = "tools\godot\Godot_v4.6-stable_win64.exe"
Start-Process $godot -ArgumentList "--path", ".", "--", "host"
Start-Sleep -Seconds 2
Start-Process $godot -ArgumentList "--path", ".", "--", "join", "127.0.0.1"
```

(注: `--`以降がget_cmdline_user_args()に入る)

- [ ] **Step 5: 検証(手動)** — run_net_test.ps1で2窓起動→接続→両画面で試合が動く/両方のキーボード操作が効く(前面ウィンドウのみ入力が入るのは正常)/HUDのtickが揃って進む/mismatch=0のまま数分。全テストも全緑
- [ ] **Step 6: コミット** — `git commit -m "M2-T5: ENet2プロセスのネット対戦シーン(フェーズ1土台)"`

---

### Task 6: 人工ロールバック負荷と30分ローカルソーク(フェーズ1ゲート)

**Files:**
- Modify: `src/net/net_match.gd` (デシンク記録の強化: mismatch時にログファイルへ)
- Create: `docs/superpowers/plans/2026-07-11-m2-gate-procedure.md` (手順書。Task 9で完成させる下書き)

- [ ] **Step 1: 人工負荷設定** — アドオンのデバッグ設定(READMEで正確なキーを確認。想定: `network/rollback/debug/rollback_ticks`)を8に設定して2プロセス対戦を10分回す。フレーム落ち・警告(`debug/physics_process_msecs`超過)をログで確認。終わったら設定を0に戻す
- [ ] **Step 2: 30分ソーク** — 同一PC2プロセスで30分連続対戦(CPU戦力で放置可: 両クライアントとも入力なしならCPUが打ち合う…はM1仕様では左チーム人間枠が無入力で止まるだけなので、レート維持のためユーザーか自動入力が必要。**自動化する場合**: net_match.gdに`--bot`引数を足し、_get_local_input相当でSimCpu.decideを使う入力ノード派生を用意する:

```gdscript
# net_input_node.gdへ追記(preloadはファイル先頭のconst群へ)
const SimCpu := preload("res://src/sim/sim_cpu.gd")

var bot := false

# _get_local_inputの先頭に:
	if bot:
		var idx: int = team * 2 + (sim_root.state.controlled_l if team == 0 else sim_root.state.controlled_r)
		return {"i": SimCpu.decide(sim_root.state, idx, sim_root.cfg)}
```

注意: SimCpu.decideは決定論(状態のみ依存)なのでロールバック安全
- [ ] **Step 3: 判定記録** — 30分(tick 108,000以上)でmismatch=0、体感遅延なしを確認しログを保存。ここまでがAIだけで完結する「フェーズ1ゲート」。結果を手順書下書きに記録
- [ ] **Step 4: コミット** — `git commit -m "M2-T6: 人工ロールバック負荷とローカル30分ソーク(フェーズ1)"`

---

### Task 7: GodotSteam導入とSteam経路(フェーズ2、ユーザー協働)

**Files:**
- Create: `addons/godotsteam/` (GDExtension版4.19.1、Codebergから)
- Create: `steam_appid.txt` (内容: `480`)
- Modify: `src/net/net_match.gd` (--steam引数でSteamMultiplayerPeerに切替)
- Modify: `.gitignore` (GodotSteamのバイナリが大きい場合の扱いを判断)

**ユーザー宿題(このタスクの前提。計画承認時に伝える):**
1. 2台目のWindows PC(Steamクライアント導入済み)
2. Steamアカウント2つ(フレンド登録済み。appid 480=Spacewarは全アカウントで利用可)
3. 両PCでSteamにログインした状態でテストに立ち会える時間

- [ ] **Step 1: 取得** — https://codeberg.org/godotsteam/godotsteam/releases から「4.19.1 GDExtension」zipを取得し、addons/godotsteamへ展開。steam_appid.txt(中身は`480`のみ)をプロジェクト直下に作成
- [ ] **Step 2: 初期化確認** — net_match.gdの_readyで(--steam時のみ)`Steam.steamInitEx(false, 480)`を呼び、戻りを表示。Steamクライアント起動中のPCで`OK`になることを確認
- [ ] **Step 3: SteamMultiplayerPeer切替** — _connect_netを分岐:

```gdscript
	if args.has("steam"):
		var speer := SteamMultiplayerPeer.new()
		if args.has("host"):
			speer.create_host(0)
			multiplayer.multiplayer_peer = speer
			multiplayer.peer_connected.connect(_on_peer_connected)
			# ロビーを作りIDをHUDに表示する(相手が--lobby <id>で入る)
			Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, 2)
			Steam.lobby_created.connect(func(_result: int, lobby_id: int) -> void:
				_hud.text = "LOBBY ID: %d (相手に伝える)" % lobby_id)
		else:
			var lobby_id := 0
			for j in args.size():
				if args[j] == "--lobby" and j + 1 < args.size():
					lobby_id = int(args[j + 1])
			Steam.lobby_joined.connect(func(joined_id: int, _perms: int, _locked: bool, _resp: int) -> void:
				var owner_id: int = Steam.getLobbyOwner(joined_id)
				speer.create_client(owner_id, 0)
				multiplayer.multiplayer_peer = speer
				multiplayer.connected_to_server.connect(_on_connected_to_server))
			Steam.joinLobby(lobby_id)
```

(注意: SteamMultiplayerPeer/ロビーAPIのシグネチャは実装時に godotsteam.com/classes/multiplayer_peer/ と lobbies ページの実物で必ず照合し、相違があればそちらを正とする。核心は「multiplayer_peerがSteam版に差し替わればSyncManager側は無改造」という一点)
- [ ] **Step 4: 2台実PCテスト(ユーザー協働)** — ホスト側`--net host steam`、参加側`--net join steam --lobby <id>`。接続→対戦→HUDでping/mismatch確認
- [ ] **Step 5: コミット** — `git commit -m "M2-T7: GodotSteam 4.19.1導入とSteam経路(Spacewar 480)"`

---

### Task 8 (条件付き): MessageSerializer圧縮

**発動条件:** フェーズ1/2のソークで`debug/message_bytes`警告(既定700バイト超)が出た場合のみ。出なければスキップしてよい(YAGNI)

**Files:**
- Create: `src/net/message_serializer.gd` (アドオンのMessageSerializerを継承しserialize_input/unserialize_inputを2〜4バイトに)
- Test: `tests/unit/test_message_serializer.gd` (往復一致)

実装方針: 入力Dictionaryは{ノードパス: {"i": int}}+メタ。パスを1バイトID表(InputL=0, InputR=1)に置換し、iは1バイト(現在5ビット)。アドオンのNetworkAdaptor登録箇所(ProjectSettings `network/rollback/classes/message_serializer`)で差し替える。詳細はREADMEの「Custom MessageSerializer」節に従う

---

### Task 9: ゲート手順書とREADME、m2タグ

**Files:**
- Create/Complete: `docs/superpowers/plans/2026-07-11-m2-gate-procedure.md`
- Modify: `README.md` (「ネット対戦(M2検証)」節)

- [ ] **Step 1: 手順書完成** — 以下を含める: フェーズ1(同一PC)の起動手順/フェーズ2(2台+Steam)の起動手順/観測項目(mismatch数・ping・体感)/合否基準(30分デシンクゼロ+ローカル同等の操作感、判定はユーザー)/不合格時の記録項目(ログ、Log Inspectorの読み方)/撤退協議の材料
- [ ] **Step 2: README追記** — 起動引数一覧(--net host / --net join [addr] / steam / --bot)、steam_appid.txtの説明、ゲート手順書への参照
- [ ] **Step 3: 全テスト全緑を確認しコミット** — `git commit -m "M2-T9: ゲート手順書とREADME"`
- [ ] **Step 4: ゲート実施(ユーザー判定)** — 合格ならユーザー確認の後 `git tag m2 && git push origin main --tags`。不合格なら手順書の記録を持って撤退協議へ

---

## 検証方法(計画全体)

- 各タスク末で run_tests.ps1 全緑(タスク1で+2、タスク4で+3、条件付きタスク8で+α)
- フェーズ1ゲート: 同一PC2プロセス+人工ロールバック負荷でmismatch=0を30分(AIのみで完結)
- フェーズ2ゲート: 2台実PC+Steam(Spacewar)で30分、mismatch=0+ユーザー官能判定(これが設計書3.3の本ゲート)

## 実行しないこと(スコープ外)

- マッチメイキングUI・ロビーブラウザ・再接続処理(M5のSteam統合本番で作る)
- 切断=敗北処理・ping上限フィルタ(設計3.4。ゲート通過後のM3以降)
- ロールバック時の演出制御(ヒットストップ等はM3の必殺技実装と同時)
- rules.json値の変更・simロジックの変更(ネット化はsimに一切触れない。触れる場合は計画を止めて相談)
