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
