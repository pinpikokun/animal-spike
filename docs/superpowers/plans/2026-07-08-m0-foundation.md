# M0 土台 (Godot 4.6 + 決定論シミュレーション + SyncTest) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animal Spike の開発土台を作る。Godot 4.6 プロジェクト、64bit整数固定小数点による決定論シミュレーション層の骨組み、同一入力2回実行の一致を検証する SyncTest、そのヘッドレス自動実行(コミット毎)までを完成させる。

**Architecture:** 2階建て構造。1階=シミュレーション層(`src/sim/`、int演算のみ、float禁止、描画と完全分離)、2階=表示層(`src/display/`、シミュレーション結果を描くだけ)。テストはカスタム軽量ランナーでヘッドレス実行し、pre-commitフックで毎コミット走らせる。

**Tech Stack:** Godot 4.6-stable (win64) / GDScript / PowerShell (テスト実行ラッパー) / git hooks

## Global Constraints

- Godot は 4.6-stable win64 に固定。バイナリは `tools/godot/` に置き gitignore する
- ダウンロード元: `https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_win64.exe.zip` (実在確認済み 2026-07-08)
- シミュレーション層 (`src/sim/` 配下) では float を一切使わない。全数値は int (GDScriptのintは64bit)
- 固定小数点は 16.16 形式 (1.0 = 65536)。`src/sim/fp.gd` 経由でのみ変換する
- 内部解像度 640x360、stretch mode = viewport、scale_mode = integer (設計書4.1節)
- ゲームルール数値は `data/rules.json` にデータ駆動で置く。JSONの数値は整数のみ許可し、読み込み時に検証する (決定論の防波堤)
- `class_name` は使わない。ヘッドレス実行でグローバルクラスキャッシュに依存しないよう、参照は全て `preload()` で行う
- リポジトリのパスに半角スペースを含む (`C:\work\git\Animal Spike`)。コマンドではパスを必ず引用符で囲む
- コミットメッセージは日本語。末尾に `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` を付ける
- 表示層の簡易描画 (円と線) は「SIM DEBUG VIEW」と明示する開発用の計器であり、ゲーム画面ではない。ゲームらしい見た目はM1でフリー素材を入れて作る (設計書1章の掟に抵触しないための区別)
- ファイル冒頭コメントに罫線・全角ダッシュ等の特殊記号を多用しない (ターミナル表示の乱れ防止)

## ファイル構成 (このプランで作るもの)

- `tools/godot/` : Godot 4.6 バイナリ置き場 (gitignore)
- `project.godot` : プロジェクト設定 (解像度、整数拡大、GL Compatibility)
- `data/rules.json` : ルール・物理の調整値 (全て整数)
- `src/sim/fp.gd` : 固定小数点演算
- `src/sim/sim_config.gd` : rules.json の読み込みと fp 単位への変換
- `src/sim/sim_state.gd` : 状態の全フィールド + シリアライズ + ハッシュ
- `src/sim/simulation.gd` : 1tick進める純粋ロジック
- `src/display/main.gd` + `src/display/main.tscn` : 開発用可視化 (SIM DEBUG VIEW)
- `tests/test_case.gd` : テスト基底 (check / check_eq)
- `tests/run_tests.gd` : ヘッドレステストランナー
- `tests/unit/test_*.gd` : ユニットテスト + SyncTest
- `run_tests.ps1` : テスト実行ラッパー
- `scripts/install_hooks.ps1` : pre-commit フック導入
- `README.md` : 開発手順

---

### Task 1: Godot 4.6 導入とプロジェクト骨格

**Files:**
- Create: `tools/godot/` (バイナリ、gitignore対象)
- Modify: `.gitignore`
- Create: `project.godot`

**Interfaces:**
- Consumes: なし (最初のタスク)
- Produces: `tools\godot\Godot_v4.6-stable_win64_console.exe` (ヘッドレス実行用)、`tools\godot\Godot_v4.6-stable_win64.exe` (ウィンドウ実行用)、有効な `project.godot`

- [ ] **Step 1: Godot 4.6 をダウンロードして展開**

PowerShell で実行:

```powershell
$repo = "C:\work\git\Animal Spike"
New-Item -ItemType Directory -Force "$repo\tools\godot" | Out-Null
$zip = "$repo\tools\godot\godot.zip"
Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_win64.exe.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath "$repo\tools\godot" -Force
Remove-Item $zip
Get-ChildItem "$repo\tools\godot"
```

Expected: `Godot_v4.6-stable_win64.exe` と `Godot_v4.6-stable_win64_console.exe` の2ファイルが現れる。

- [ ] **Step 2: バージョン確認**

```powershell
& "C:\work\git\Animal Spike\tools\godot\Godot_v4.6-stable_win64_console.exe" --version
```

Expected: `4.6.stable.official` で始まる文字列。

- [ ] **Step 3: .gitignore に tools/ を追加**

`.gitignore` の末尾に追記:

```
# Godotバイナリ(各自ダウンロード)
tools/
```

- [ ] **Step 4: project.godot を作成**

`project.godot` (新規、以下の内容そのまま):

```ini
; Animal Spike (仮称) - Godot 4.6
config_version=5

[application]

config/name="Animal Spike"
config/features=PackedStringArray("4.6", "GL Compatibility")

[display]

window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

[physics]

common/physics_ticks_per_second=60

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
```

注意: `run/main_scene` はまだ設定しない (Task 8 でシーンを作ってから追加する)。

- [ ] **Step 5: インポート実行で設定の妥当性を確認**

```powershell
& "C:\work\git\Animal Spike\tools\godot\Godot_v4.6-stable_win64_console.exe" --headless --path "C:\work\git\Animal Spike" --import
```

Expected: エラーなく終了し `.godot/` ディレクトリが生成される (gitignore済み)。

- [ ] **Step 6: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add .gitignore project.godot
git -C "C:\work\git\Animal Spike" commit -m "M0: Godot 4.6プロジェクト骨格(640x360、整数拡大)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: テストランナーと自動実行 (CIの土台)

**Files:**
- Create: `tests/test_case.gd`
- Create: `tests/run_tests.gd`
- Create: `tests/unit/test_runner_selfcheck.gd`
- Create: `run_tests.ps1`
- Create: `scripts/install_hooks.ps1`

**Interfaces:**
- Consumes: Task 1 の Godot バイナリ
- Produces: テスト基底クラス (`check(cond: bool, msg: String)`, `check_eq(actual, expected, msg)` と `failures: Array[String]`)。テストは `tests/unit/test_*.gd` に置き、`extends "res://tests/test_case.gd"` して `test_` で始まるメソッドを書けば自動発見される。`run_tests.ps1` は全テスト成功で exit 0、失敗で exit 1

- [ ] **Step 1: テスト基底クラスを書く**

`tests/test_case.gd` (新規):

```gdscript
# テスト基底。check系メソッドで失敗を蓄積し、ランナーが回収する
extends RefCounted

var failures: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [msg, str(expected), str(actual)])
```

- [ ] **Step 2: テストランナーを書く**

`tests/run_tests.gd` (新規):

```gdscript
# ヘッドレステストランナー
# 使い方: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

const TEST_DIR := "res://tests/unit"

func _init() -> void:
	var failed := 0
	var total := 0
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("テストディレクトリが開けない: " + TEST_DIR)
		quit(1)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	for name in names:
		var script: GDScript = load(TEST_DIR + "/" + name)
		var t: Object = script.new()
		for m in script.get_script_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_"):
				continue
			total += 1
			t.failures.clear()
			t.call(method)
			if t.failures.is_empty():
				print("PASS  %s.%s" % [name, method])
			else:
				failed += 1
				print("FAIL  %s.%s" % [name, method])
				for msg in t.failures:
					print("      " + msg)
	print("----")
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
```

- [ ] **Step 3: 実行ラッパーを書く**

`run_tests.ps1` (新規):

```powershell
# 全テスト(SyncTest含む)をヘッドレス実行する
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Host "Godotが見つからない: $godot (README参照)"
    exit 1
}
& $godot --headless --path $PSScriptRoot --script res://tests/run_tests.gd
exit $LASTEXITCODE
```

- [ ] **Step 4: 空の状態でランナーを実行**

```powershell
New-Item -ItemType Directory -Force "C:\work\git\Animal Spike\tests\unit" | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: `0 tests, 0 failed` と表示され exit 0。

- [ ] **Step 5: ランナー自己検証テストを書く**

`tests/unit/test_runner_selfcheck.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

func test_runner_works() -> void:
	check_eq(1 + 1, 2, "算数が壊れていない")
```

再実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: `PASS  test_runner_selfcheck.gd.test_runner_works` と `1 tests, 0 failed`、exit 0。

- [ ] **Step 6: pre-commit フックを導入 (毎コミットでテスト)**

`scripts/install_hooks.ps1` (新規):

```powershell
# pre-commitフックを導入する。コミット毎に全テストが走る
$root = Split-Path $PSScriptRoot -Parent
$hook = Join-Path $root ".git\hooks\pre-commit"
$body = @'
#!/bin/sh
cd "$(git rev-parse --show-toplevel)" || exit 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File run_tests.ps1
'@
[System.IO.File]::WriteAllText($hook, $body.Replace("`r`n", "`n"))
Write-Host "pre-commitフックを導入した: $hook"
```

実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\scripts\install_hooks.ps1"
```

Expected: フック導入メッセージ。

- [ ] **Step 7: Commit (フックが動くことも同時に確認される)**

```powershell
git -C "C:\work\git\Animal Spike" add tests/ run_tests.ps1 scripts/
git -C "C:\work\git\Animal Spike" commit -m "M0: テストランナーとpre-commitフック(SyncTest自動化の土台)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: コミット前にテストが走り PASS、コミット成功。

---

### Task 3: 固定小数点演算 fp.gd

**Files:**
- Create: `src/sim/fp.gd`
- Test: `tests/unit/test_fp.gd`

**Interfaces:**
- Consumes: Task 2 のテスト基盤
- Produces: `const FP := preload("res://src/sim/fp.gd")` で使う静的関数群。`FP.ONE: int = 65536`、`FP.from_int(v: int) -> int`、`FP.to_int(v: int) -> int` (床方向丸め)、`FP.mul(a: int, b: int) -> int`、`FP.div(a: int, b: int) -> int` (0方向丸め)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_fp.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")

func test_roundtrip() -> void:
	check_eq(FP.to_int(FP.from_int(5)), 5, "5の往復")
	check_eq(FP.to_int(FP.from_int(-3)), -3, "-3の往復")
	check_eq(FP.ONE, 65536, "ONE")

func test_mul() -> void:
	check_eq(FP.mul(FP.from_int(3), FP.from_int(4)), FP.from_int(12), "3x4")
	check_eq(FP.mul(FP.ONE / 2, FP.from_int(6)), FP.from_int(3), "0.5x6")
	check_eq(FP.mul(FP.from_int(-3), FP.from_int(4)), FP.from_int(-12), "負の積")

func test_div() -> void:
	check_eq(FP.div(FP.from_int(12), FP.from_int(4)), FP.from_int(3), "12/4")
	check_eq(FP.div(FP.from_int(1), FP.from_int(2)), FP.ONE / 2, "1/2")

func test_to_int_floors_negative() -> void:
	# 算術シフトなので負数は床方向。この挙動を回帰検知のため固定する
	check_eq(FP.to_int(-1), -1, "微小負数の床")
```

- [ ] **Step 2: 失敗を確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: FAIL (fp.gd が存在しないため load エラーまたは FAIL 表示)。

- [ ] **Step 3: 実装を書く**

`src/sim/fp.gd` (新規):

```gdscript
# 固定小数点演算 16.16 (1.0 = 65536)。int64のみ、float禁止
# シミュレーション層の数値は全てこの形式で持つ
extends RefCounted

const SHIFT := 16
const ONE := 1 << SHIFT

static func from_int(v: int) -> int:
	return v << SHIFT

static func to_int(v: int) -> int:
	return v >> SHIFT

static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT

static func div(a: int, b: int) -> int:
	return (a << SHIFT) / b
```

- [ ] **Step 4: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS、`5 tests, 0 failed`。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/fp.gd tests/unit/test_fp.gd
git -C "C:\work\git\Animal Spike" commit -m "M0: 固定小数点演算fp.gd(16.16、float禁止の土台)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: ルール設定のデータ駆動読み込み

**Files:**
- Create: `data/rules.json`
- Create: `src/sim/sim_config.gd`
- Test: `tests/unit/test_config.gd`

**Interfaces:**
- Consumes: `FP` (Task 3)
- Produces: `preload("res://src/sim/sim_config.gd").new()` で既定の rules.json を読む設定オブジェクト。フィールド: `tick_rate: int`、fp単位の `court_width` `court_height` `floor_y` `gravity` (fp/tick^2) `move_speed` `jump_speed` (fp/tick) `ball_radius`、`ball_bounce_num: int` `ball_bounce_den: int` (反発率の分数)、`points_to_win: int`、`deuce: bool`。JSONに整数以外の数値や欠損キーがあれば assert で即死する

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_config.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")

func test_loads_default_rules() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.tick_rate, 60, "tick_rate")
	check_eq(cfg.court_width, FP.from_int(640), "court_width")
	check_eq(cfg.floor_y, FP.from_int(320), "floor_y")
	check_eq(cfg.points_to_win, 15, "15点先取")
	check_eq(cfg.deuce, true, "デュース有")

func test_values_are_int() -> void:
	var cfg = SimConfig.new()
	check(typeof(cfg.gravity) == TYPE_INT, "gravityがint")
	check(typeof(cfg.move_speed) == TYPE_INT, "move_speedがint")
	check(typeof(cfg.jump_speed) == TYPE_INT, "jump_speedがint")
	check(cfg.gravity > 0, "gravityが正")
	check(cfg.move_speed > 0, "move_speedが正")
```

- [ ] **Step 2: 失敗を確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: FAIL (sim_config.gd 不在)。

- [ ] **Step 3: ルールJSONと読み込みを実装**

`data/rules.json` (新規、数値は全て整数。単位はピクセルと秒):

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
	"deuce": 1
}
```

`src/sim/sim_config.gd` (新規):

```gdscript
# ルール調整値の読み込み。JSONの数値は整数のみ許可(決定論の防波堤)
# 速度や重力は読み込み時にtick単位のfpへ変換する
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const DEFAULT_PATH := "res://data/rules.json"

var tick_rate: int
var court_width: int
var court_height: int
var floor_y: int
var gravity: int
var move_speed: int
var jump_speed: int
var ball_radius: int
var ball_bounce_num: int
var ball_bounce_den: int
var points_to_win: int
var deuce: bool

func _init(path: String = DEFAULT_PATH) -> void:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "rules.jsonが読めない: " + path)
	var raw: Dictionary = parsed
	tick_rate = _int_of(raw, "tick_rate")
	court_width = FP.from_int(_int_of(raw, "court_width_px"))
	court_height = FP.from_int(_int_of(raw, "court_height_px"))
	floor_y = FP.from_int(_int_of(raw, "floor_y_px"))
	gravity = FP.from_int(_int_of(raw, "gravity_px_s2")) / (tick_rate * tick_rate)
	move_speed = FP.from_int(_int_of(raw, "move_speed_px_s")) / tick_rate
	jump_speed = FP.from_int(_int_of(raw, "jump_speed_px_s")) / tick_rate
	ball_radius = FP.from_int(_int_of(raw, "ball_radius_px"))
	ball_bounce_num = _int_of(raw, "ball_bounce_pct")
	ball_bounce_den = 100
	points_to_win = _int_of(raw, "points_to_win")
	deuce = _int_of(raw, "deuce") != 0

func _int_of(raw: Dictionary, key: String) -> int:
	assert(raw.has(key), "rules.jsonにキーが無い: " + key)
	var v: Variant = raw[key]
	var t := typeof(v)
	assert(t == TYPE_FLOAT or t == TYPE_INT, "数値でない: " + key)
	var f := float(v)
	assert(f == floor(f), "整数でない値がある: " + key)
	return int(f)
```

- [ ] **Step 4: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS、`7 tests, 0 failed`。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add data/rules.json src/sim/sim_config.gd tests/unit/test_config.gd
git -C "C:\work\git\Animal Spike" commit -m "M0: ルール設定のデータ駆動読み込み(整数のみ許可)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: シミュレーション状態とハッシュ

**Files:**
- Create: `src/sim/sim_state.gd`
- Test: `tests/unit/test_state.gd`

**Interfaces:**
- Consumes: なし (自己完結)
- Produces: `preload("res://src/sim/sim_state.gd").new()`。フィールド: `tick: int`、`players: Array[Player]` (4体、`Player` は内部クラスで `x y vx vy on_ground` 全てint、on_groundは0/1)、`ball_x ball_y ball_vx ball_vy: int`。メソッド: `to_int_array() -> Array[int]` (固定順序シリアライズ、長さ25)、`state_hash() -> int` (FNV-1a 64bit)

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_state.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")

func test_equal_states_equal_hash() -> void:
	var a = SimState.new()
	var b = SimState.new()
	check_eq(a.state_hash(), b.state_hash(), "初期状態のハッシュが一致")

func test_hash_changes_on_diff() -> void:
	var a = SimState.new()
	var b = SimState.new()
	b.ball_x = 1
	check(a.state_hash() != b.state_hash(), "1bitの差でハッシュが変わる")
	var c = SimState.new()
	c.players[3].vy = -1
	check(a.state_hash() != c.state_hash(), "プレイヤー差分でも変わる")

func test_serialize_length() -> void:
	# tick(1) + プレイヤー4体x5 + ボール4 = 25
	check_eq(SimState.new().to_int_array().size(), 25, "シリアライズ長")
```

- [ ] **Step 2: 失敗を確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: FAIL (sim_state.gd 不在)。

- [ ] **Step 3: 実装を書く**

`src/sim/sim_state.gd` (新規):

```gdscript
# シミュレーションの全状態。全フィールドint(fp)。float禁止
# フィールドを増やしたら必ずto_int_arrayにも足すこと(ハッシュ対象漏れはデシンクの温床)
extends RefCounted

const PLAYER_COUNT := 4

class Player:
	var x: int = 0
	var y: int = 0
	var vx: int = 0
	var vy: int = 0
	var on_ground: int = 1

var tick: int = 0
var players: Array[Player] = []
var ball_x: int = 0
var ball_y: int = 0
var ball_vx: int = 0
var ball_vy: int = 0

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
	out.append(ball_x)
	out.append(ball_y)
	out.append(ball_vx)
	out.append(ball_vy)
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

- [ ] **Step 4: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS、`10 tests, 0 failed`。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/sim_state.gd tests/unit/test_state.gd
git -C "C:\work\git\Animal Spike" commit -m "M0: シミュレーション状態とFNVハッシュ(デシンク検出の目)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: シミュレーション本体 (移動・重力・壁反射)

**Files:**
- Create: `src/sim/simulation.gd`
- Test: `tests/unit/test_simulation.gd`

**Interfaces:**
- Consumes: `FP` (Task 3)、`SimConfig` (Task 4)、`SimState` (Task 5)
- Produces: `preload("res://src/sim/simulation.gd")`。定数 `IN_LEFT := 1` `IN_RIGHT := 2` `IN_JUMP := 4` (入力ビットマスク)。静的メソッド `step(state, inputs: Array[int], cfg) -> void` が状態を1tick進める。inputs はプレイヤー番号順のビットマスク配列 (不足分は入力なし扱い)。M1以降このメソッドにレシーブ・トス・スパイク・得点を足していく

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_simulation.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _new_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.y = cfg.floor_y
	return [s, cfg]

func test_tick_advances() -> void:
	var w := _new_world()
	Simulation.step(w[0], [0, 0, 0, 0], w[1])
	check_eq(w[0].tick, 1, "tickが進む")

func test_move_right_speed() -> void:
	var w := _new_world()
	var s = w[0]
	for i in 60:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], w[1])
	var moved := FP.to_int(s.players[0].x)
	check(moved >= 175 and moved <= 185, "1秒で約180px移動 actual=" + str(moved))

func test_jump_and_land() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "ジャンプで空中へ")
	check(s.players[0].y < cfg.floor_y, "上昇している")
	var landed := false
	for i in 300:
		Simulation.step(s, [0, 0, 0, 0], cfg)
		if s.players[0].on_ground == 1:
			landed = true
			break
	check(landed, "300tick以内に着地する")
	check_eq(s.players[0].y, cfg.floor_y, "床にスナップ")

func test_no_double_jump() -> void:
	var w := _new_world()
	var s = w[0]
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], w[1])
	var vy_air: int = s.players[0].vy
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], w[1])
	check(s.players[0].vy > vy_air, "空中で再ジャンプできない(重力で減速のみ)")

func test_player_stays_in_court() -> void:
	var w := _new_world()
	var s = w[0]
	for i in 600:
		Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], w[1])
	check_eq(s.players[0].x, 0, "左端で止まる")

func test_ball_wall_bounce() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.ball_radius + FP.from_int(2)
	s.ball_y = FP.from_int(100)
	s.ball_vx = -FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "左壁で反射して右向きになる")
	check(s.ball_x >= cfg.ball_radius, "壁にめり込まない")

func test_ball_floor_bounce_decays() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(320)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(6)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "床で反射して上向きになる")
	check(-s.ball_vy < FP.from_int(6), "反発で減衰する")
```

- [ ] **Step 2: 失敗を確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: FAIL (simulation.gd 不在)。

- [ ] **Step 3: 実装を書く**

`src/sim/simulation.gd` (新規):

```gdscript
# シミュレーション本体。1tick進める純粋ロジック
# int演算のみ。ここにfloatを書いたらSyncTest以前にレビューで即アウト
extends RefCounted

const FP := preload("res://src/sim/fp.gd")

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_JUMP := 4

static func step(state, inputs: Array[int], cfg) -> void:
	state.tick += 1
	for i in state.players.size():
		var input: int = inputs[i] if i < inputs.size() else 0
		_step_player(state.players[i], input, cfg)
	_step_ball(state, cfg)

static func _step_player(p, input: int, cfg) -> void:
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
	p.x = clampi(p.x + p.vx, 0, cfg.court_width)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1

static func _step_ball(s, cfg) -> void:
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
```

- [ ] **Step 4: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS、`17 tests, 0 failed`。

- [ ] **Step 5: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add src/sim/simulation.gd tests/unit/test_simulation.gd
git -C "C:\work\git\Animal Spike" commit -m "M0: シミュレーション本体(移動・重力・壁反射、全int演算)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: SyncTest (決定論の生命線)

**Files:**
- Test: `tests/unit/test_sync.gd`

**Interfaces:**
- Consumes: Task 3〜6 の全モジュール
- Produces: 同一入力列を2回流して全チェックポイントのハッシュ一致を検証するテスト。以後、シミュレーション層への全変更はこのテストを通過しなければコミットできない (pre-commitフック経由)

- [ ] **Step 1: SyncTest を書く**

`tests/unit/test_sync.gd` (新規):

```gdscript
extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

const TICKS := 3600

# 決定論の生命線。同一入力列を2回流して全ハッシュが一致すること
# ここが落ちたら最優先で直す。floatや未初期化状態の混入が疑わしい

func _next_rand(s: int) -> int:
	# xorshift64。乱数も整数のみで作る
	s ^= s << 13
	s ^= s >> 7
	s ^= s << 17
	return s

func _run_once() -> Array[int]:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(220)
	s.players[2].x = FP.from_int(420)
	s.players[3].x = FP.from_int(540)
	s.ball_x = FP.from_int(320)
	s.ball_y = FP.from_int(60)
	var hashes: Array[int] = []
	var rng := 123456789
	for t in TICKS:
		var inputs: Array[int] = []
		for i in 4:
			rng = _next_rand(rng)
			inputs.append(rng & 7)
		Simulation.step(s, inputs, cfg)
		if t % 60 == 0:
			hashes.append(s.state_hash())
	hashes.append(s.state_hash())
	return hashes

func test_synctest_60_seconds() -> void:
	var a := _run_once()
	var b := _run_once()
	check_eq(a.size(), b.size(), "チェックポイント数が一致")
	for i in a.size():
		if a[i] != b[i]:
			check(false, "デシンク検出 checkpoint=" + str(i))
			return
```

- [ ] **Step 2: テストが通ることを確認**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: 全PASS、`18 tests, 0 failed`。SyncTest は 3600tick x 2回でも数秒以内に終わる。

- [ ] **Step 3: 決定論破壊を検出できることを実証 (一時的な破壊テスト)**

`src/sim/simulation.gd` の `_step_ball` 先頭に一時的に1行足す:

```gdscript
	s.ball_vx += int(randf() * 3.0) - 1
```

実行:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: `FAIL test_sync.gd.test_synctest_60_seconds` と「デシンク検出」。確認後、**必ずこの行を削除**して再実行し全PASSに戻す。

- [ ] **Step 4: Commit**

```powershell
git -C "C:\work\git\Animal Spike" add tests/unit/test_sync.gd
git -C "C:\work\git\Animal Spike" commit -m "M0: SyncTest導入(同一入力2回実行のハッシュ一致検証)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 表示層スケルトン (SIM DEBUG VIEW)

**Files:**
- Create: `src/display/main.gd`
- Create: `src/display/main.tscn`
- Modify: `project.godot` ([application] セクションに main_scene 追加)

**Interfaces:**
- Consumes: Task 3〜6 の全モジュール
- Produces: 起動可能な Godot プロジェクト。640x360 の内部解像度が整数拡大で表示され、シミュレーション層が60tpsで回り、キーボード入力(矢印+Z)がシミュレーションに流れることを目視確認できる。これは開発用計器であり、M1 でゲーム画面に置き換える

- [ ] **Step 1: 表示スクリプトを書く**

`src/display/main.gd` (新規):

```gdscript
# SIM DEBUG VIEW。シミュレーション層の動作確認用の開発計器
# ゲームとしての見た目はM1でフリー素材を入れて作る。ここは表示層なのでfloat使用OK
extends Node2D

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

var cfg
var state
var label: Label

func _ready() -> void:
	cfg = SimConfig.new()
	state = SimState.new()
	for p in state.players:
		p.y = cfg.floor_y
	state.players[0].x = FP.from_int(100)
	state.players[1].x = FP.from_int(220)
	state.players[2].x = FP.from_int(420)
	state.players[3].x = FP.from_int(540)
	state.ball_x = FP.from_int(320)
	state.ball_y = FP.from_int(60)
	Engine.physics_ticks_per_second = cfg.tick_rate
	label = Label.new()
	label.position = Vector2(4, 4)
	add_child(label)

func _physics_process(_delta: float) -> void:
	var input := 0
	if Input.is_key_pressed(KEY_LEFT):
		input |= Simulation.IN_LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		input |= Simulation.IN_RIGHT
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_SPACE):
		input |= Simulation.IN_JUMP
	Simulation.step(state, [input, 0, 0, 0], cfg)
	label.text = "SIM DEBUG VIEW (開発用計器)\ntick=%d\nhash=%s\n矢印キーで移動 Zでジャンプ" % [
		state.tick, String.num_uint64(state.state_hash(), 16)]
	queue_redraw()

func _draw() -> void:
	var fy := float(FP.to_int(cfg.floor_y))
	draw_line(Vector2(0, fy), Vector2(640, fy), Color(0.4, 0.4, 0.55))
	for p in state.players:
		draw_circle(Vector2(FP.to_int(p.x), FP.to_int(p.y)), 6.0, Color(0.9, 0.8, 0.3))
	draw_circle(
		Vector2(FP.to_int(state.ball_x), FP.to_int(state.ball_y)),
		float(FP.to_int(cfg.ball_radius)), Color(0.95, 0.95, 0.95))
```

- [ ] **Step 2: シーンファイルを書く**

`src/display/main.tscn` (新規):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/display/main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
```

- [ ] **Step 3: project.godot にメインシーンを設定**

`project.godot` の `[application]` セクションに1行追加:

```ini
run/main_scene="res://src/display/main.tscn"
```

- [ ] **Step 4: ヘッドレスで起動確認**

```powershell
& "C:\work\git\Animal Spike\tools\godot\Godot_v4.6-stable_win64_console.exe" --headless --path "C:\work\git\Animal Spike" --quit-after 180
```

Expected: スクリプトエラーなしで正常終了 (約3秒分のフレームを回して終了)。

- [ ] **Step 5: ウィンドウ表示で起動確認**

```powershell
& "C:\work\git\Animal Spike\tools\godot\Godot_v4.6-stable_win64.exe" --path "C:\work\git\Animal Spike" --quit-after 600
```

Expected: 1280x720 ウィンドウ (内部640x360の2倍整数拡大) が約10秒表示され、床線・キャラ位置の点・落下してバウンドするボールと「SIM DEBUG VIEW」の文字が見える。エラーなく自動終了。

- [ ] **Step 6: 全テスト再実行と Commit**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
git -C "C:\work\git\Animal Spike" add src/display/ project.godot
git -C "C:\work\git\Animal Spike" commit -m "M0: 表示層スケルトン(SIM DEBUG VIEW、60tps駆動)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: README と M0 完了タグ

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: 全タスクの成果
- Produces: 開発手順書。git タグ `m0` でマイルストーン完了を記録

- [ ] **Step 1: README を書く**

`README.md` (新規):

```markdown
# Animal Spike (仮称)

1994年のPC-98フリーソフト「VOLLEY BALL 2on2」の精神的リメイク。
可愛い動物のチビキャラが2対2でバレーボールをする対戦ゲーム。Steam販売予定。

- 設計書: docs/superpowers/specs/2026-07-08-animal-spike-design.md
- 実装計画: docs/superpowers/plans/

## 開発環境の準備

1. Godot 4.6-stable win64 を下記からダウンロードして tools/godot/ に展開する
   https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_win64.exe.zip
2. pre-commitフックを導入する
   powershell -File scripts/install_hooks.ps1

## コマンド

- 全テスト実行: `powershell -File run_tests.ps1`
- ゲーム起動: `tools\godot\Godot_v4.6-stable_win64.exe --path .`
- エディタ起動: `tools\godot\Godot_v4.6-stable_win64.exe --path . --editor`

## アーキテクチャ (2階建て)

- src/sim/ : シミュレーション層。64bit整数の固定小数点(16.16)のみ。float禁止。
  同じ入力なら必ず同じ結果になる(決定論)。オンライン対戦のロールバックの土台
- src/display/ : 表示層。シミュレーション結果を描くだけ。float使用可
- data/rules.json : ゲームルールと物理の調整値。全て整数
- tests/ : ユニットテストとSyncTest(同一入力2回実行の一致検証)

## 掟

- シミュレーション層にfloatを書かない(SyncTestが検出する)
- 状態フィールドを増やしたら sim_state.gd の to_int_array に必ず追加する
- ゲーム画面にプレースホルダー(四角や丸)を使わない。SIM DEBUG VIEWは開発計器で例外
```

- [ ] **Step 2: 最終確認 (全テスト + 起動)**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\work\git\Animal Spike\run_tests.ps1"
```

Expected: `18 tests, 0 failed`、exit 0。

- [ ] **Step 3: Commit とタグ**

```powershell
git -C "C:\work\git\Animal Spike" add README.md
git -C "C:\work\git\Animal Spike" commit -m "M0: README(開発手順と掟)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git -C "C:\work\git\Animal Spike" tag m0
```

Expected: タグ `m0` が作られ M0 完了。

---

## M0 のスコープ外 (次のプランで扱う)

- ネット・レシーブ・トス・スパイク・得点・キャラ切り替え: M1プラン (フリー素材の調達込み)
- godot-rollback-netcode / GodotSteam の導入と Delta Rollback フォーク比較: M2プラン
- CRT/スキャンラインフィルター: M1プラン (解像度官能確認と同時)
- トラックB (キャラクターゼロ): 別ワークストリーム。ユーザーの参照画像待ち
