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
	var stun: int = 0  # パワーボールを受けた硬直(移動・ヒット不可)の残りtick
	# CPUプロファイル(8bit x 7欄: 能力/反応遅延/狙い誤差/ミス率/ジャスト率/予測深度/配球IQ)。
	# 欄の割当はsim_cpu.gdのP_*。既定は最強プリセット(sim_cpu.PRESET_MAXと一致、テストで保証)
	var cpu: int = 848543938315807

var tick: int = 0
var players: Array[Player] = []
var ball_x: int = 0
var ball_y: int = 0
var ball_vx: int = 0
var ball_vy: int = 0
var ball_spin: int = 0  # 累積回転量(横移動由来)。表示層が回転フレームの導出に使う
var ball_power: int = 0  # 1=パーフェクトスパイク由来のパワーボール(受けた側がスタンする)
var last_hit_tick: int = 0  # 最後にヒット/サーブが起きたtick。CPUの反応遅延と乱数キーの主軸
var serve_aim: int = 25  # サーブの照準角(垂直から何度ネット側へ倒すか。0=真上..60=低い弾道)
var serve_pow: int = 100  # サーブ威力(%)。上下キーで60..130を選ぶ
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
		out.append(p.stun)
		out.append(p.cpu)
	out.append(ball_x)
	out.append(ball_y)
	out.append(ball_vx)
	out.append(ball_vy)
	out.append(ball_spin)
	out.append(ball_power)
	out.append(last_hit_tick)
	out.append(serve_aim)
	out.append(serve_pow)
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
		p.stun = arr[k]; k += 1
		p.cpu = arr[k]; k += 1
	ball_x = arr[k]; k += 1
	ball_y = arr[k]; k += 1
	ball_vx = arr[k]; k += 1
	ball_vy = arr[k]; k += 1
	ball_spin = arr[k]; k += 1
	ball_power = arr[k]; k += 1
	last_hit_tick = arr[k]; k += 1
	serve_aim = arr[k]; k += 1
	serve_pow = arr[k]; k += 1
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

func state_hash() -> int:
	# FNV-1a 64bit。オフセット値はint64符号付き表現
	# GDScriptのint64はオーバーフロー時にラップするのでそのまま使える
	var h := -3750763034362895579
	for v in to_int_array():
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h
