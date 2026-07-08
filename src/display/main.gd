# SIM DEBUG VIEW。シミュレーション層の動作確認用の開発計器
# ゲームとしての見た目はM1でフリー素材を入れて作る。ここは表示層なのでfloat使用OK
extends Node2D

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

var cfg
var state
var label: Label

func _ready() -> void:
	cfg = SimConfig.new()
	if not cfg.valid:
		push_error("rules.jsonの読み込みに失敗したため起動を中止する")
		get_tree().quit(1)
		return
	state = SimState.new()
	Simulation.reset_match(state, cfg, 0)
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
	if Input.is_key_pressed(KEY_X):
		input |= Simulation.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= Simulation.IN_SWITCH
	# 右チームは完全CPU。操作キャラ枠の入力もCPUが生成する(サーブ止まり防止)
	var cpu_r: int = SimCpu.decide(state, 2 + state.controlled_r, cfg)
	Simulation.tick(state, [input, cpu_r], cfg)
	label.text = "SIM DEBUG VIEW (開発用計器)\n%d - %d  phase=%d touches=%d\ntick=%d\n矢印:移動 Z:ジャンプ X:アクション C:交代" % [
		state.score_l, state.score_r, state.phase, state.touches, state.tick]
	queue_redraw()

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
