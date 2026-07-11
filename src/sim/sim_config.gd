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
var net_x: int
var net_top_y: int
var net_half_w: int
var player_reach: int
var serve_hold_height: int
var serve_line: int
var ball_rest_speed: int
var bump_up_speed: int
var bump_fwd_speed: int
var toss_fwd_vy: int
var toss_fwd_vx: int
var toss_mid_vx: int
var hit_inertia_num: int
var hit_inertia_den: int
var spike_vx: int
var spike_vy: int
var serve_vx: int
var serve_vy: int
var serve_soft_vx: int
var serve_soft_vy: int
var net_repel: int
var hit_cooldown_ticks: int
var point_pause_ticks: int
var serve_delay_ticks: int
var max_touches: int
var spawn_back_px: int
var spawn_front_px: int

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
	net_x = FP.from_int(_int_of(raw, "net_x_px"))
	net_top_y = FP.from_int(_int_of(raw, "net_top_y_px"))
	net_half_w = FP.from_int(_int_of(raw, "net_half_w_px"))
	player_reach = FP.from_int(_int_of(raw, "player_reach_px"))
	serve_hold_height = FP.from_int(_int_of(raw, "serve_hold_height_px"))
	serve_line = FP.from_int(_int_of(raw, "serve_line_px"))
	ball_rest_speed = FP.from_int(_int_of(raw, "ball_rest_speed_px_s")) / tick_rate
	bump_up_speed = FP.from_int(_int_of(raw, "bump_up_speed_px_s")) / tick_rate
	bump_fwd_speed = FP.from_int(_int_of(raw, "bump_fwd_speed_px_s")) / tick_rate
	toss_fwd_vy = FP.from_int(_int_of(raw, "toss_fwd_vy_px_s")) / tick_rate
	toss_fwd_vx = FP.from_int(_int_of(raw, "toss_fwd_vx_px_s")) / tick_rate
	toss_mid_vx = FP.from_int(_int_of(raw, "toss_mid_vx_px_s")) / tick_rate
	hit_inertia_num = _int_of(raw, "hit_inertia_pct")
	hit_inertia_den = 100
	spike_vx = FP.from_int(_int_of(raw, "spike_vx_px_s")) / tick_rate
	spike_vy = FP.from_int(_int_of(raw, "spike_vy_px_s")) / tick_rate
	serve_vx = FP.from_int(_int_of(raw, "serve_vx_px_s")) / tick_rate
	serve_vy = FP.from_int(_int_of(raw, "serve_vy_px_s")) / tick_rate
	serve_soft_vx = FP.from_int(_int_of(raw, "serve_soft_vx_px_s")) / tick_rate
	serve_soft_vy = FP.from_int(_int_of(raw, "serve_soft_vy_px_s")) / tick_rate
	net_repel = FP.from_int(_int_of(raw, "net_repel_px_s")) / tick_rate
	hit_cooldown_ticks = _int_of(raw, "hit_cooldown_ticks")
	point_pause_ticks = _int_of(raw, "point_pause_ticks")
	serve_delay_ticks = _int_of(raw, "serve_delay_ticks")
	max_touches = _int_of(raw, "max_touches")
	spawn_back_px = _int_of(raw, "spawn_back_px")
	spawn_front_px = _int_of(raw, "spawn_front_px")

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
