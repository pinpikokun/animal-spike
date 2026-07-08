# ルール調整値の読み込み。JSONの数値は整数のみ許可(決定論の防波堤)
# 速度や重力は読み込み時にtick単位のfpへ変換する
# 検証はassertではなく実行時チェック(assertはリリースビルドで消えるため)。
# 失敗時はvalid=falseになる。呼び出し側はvalidを確認すること
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const DEFAULT_PATH := "res://data/rules.json"

var valid: bool = true
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
	if not (parsed is Dictionary):
		_fail("rules.jsonが読めない: " + path)
		return
	var raw: Dictionary = parsed
	tick_rate = _int_of(raw, "tick_rate")
	if tick_rate <= 0:
		# ゼロ除算防止。以降の変換はtick_rateが正であることが前提
		_fail("tick_rateが不正: " + str(tick_rate))
		return
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
	if not raw.has(key):
		_fail("rules.jsonにキーが無い: " + key)
		return 0
	var v: Variant = raw[key]
	var t := typeof(v)
	if t == TYPE_INT:
		return v
	if t != TYPE_FLOAT:
		_fail("数値でない: " + key)
		return 0
	var f: float = v  # float-ok: JSONの数値はfloatで届く。ここで整数値のみ通す
	if f != floor(f):  # float-ok: 整数値チェック(JSON境界のみ)
		_fail("整数でない値がある: " + key)
		return 0
	return int(f)  # float-ok: 検証済みの整数値をintへ確定

func _fail(msg: String) -> void:
	valid = false
	push_error(msg)
